#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ReadSpec {
    const char *name;
    DWORD_PTR address;
    SIZE_T length; /* 0 = one u32; otherwise a byte range emitted as hex */
} ReadSpec;

#define MAX_RANGE_LENGTH 0x40000u

static void json_string(FILE *out, const char *value) {
    fputc('"', out);
    for (const unsigned char *p = (const unsigned char *)value; *p; ++p) {
        switch (*p) {
            case '\\':
                fputs("\\\\", out);
                break;
            case '"':
                fputs("\\\"", out);
                break;
            case '\b':
                fputs("\\b", out);
                break;
            case '\f':
                fputs("\\f", out);
                break;
            case '\n':
                fputs("\\n", out);
                break;
            case '\r':
                fputs("\\r", out);
                break;
            case '\t':
                fputs("\\t", out);
                break;
            default:
                if (*p < 0x20) {
                    fprintf(out, "\\u%04x", *p);
                } else {
                    fputc(*p, out);
                }
                break;
        }
    }
    fputc('"', out);
}

static int parse_read_u32(const char *arg, ReadSpec *spec) {
    const char *equals = strchr(arg, '=');
    char *end = NULL;
    unsigned long address = 0;

    if (equals == NULL || equals == arg || equals[1] == '\0') {
        return 0;
    }
    for (const char *p = arg; p < equals; ++p) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '_' || *p == '-' || *p == '.')) {
            return 0;
        }
    }
    if (strncmp(equals + 1, "0x", 2) != 0 && strncmp(equals + 1, "0X", 2) != 0) {
        return 0;
    }
    address = strtoul(equals + 1, &end, 16);
    if (end == NULL || *end != '\0') {
        return 0;
    }
    spec->name = arg;
    spec->address = (DWORD_PTR)address;
    spec->length = 0;
    return 1;
}

/* name=0xADDR:0xLEN — a bounded byte range (at most MAX_RANGE_LENGTH), emitted as lowercase hex. */
static int parse_read_bytes(const char *arg, ReadSpec *spec) {
    const char *colon = strchr(arg, ':');
    char *end = NULL;
    unsigned long length = 0;
    char head[128];

    if (colon == NULL || (size_t)(colon - arg) >= sizeof(head) || strncmp(colon + 1, "0x", 2) != 0) {
        return 0;
    }
    memcpy(head, arg, (size_t)(colon - arg));
    head[colon - arg] = '\0';
    if (!parse_read_u32(head, spec)) {
        return 0;
    }
    length = strtoul(colon + 1, &end, 16);
    if (end == NULL || *end != '\0' || length == 0 || length > MAX_RANGE_LENGTH) {
        return 0;
    }
    spec->name = arg;
    spec->length = (SIZE_T)length;
    return 1;
}

static int process_exists(DWORD pid) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32 entry;
    int found = 0;

    if (snapshot == INVALID_HANDLE_VALUE) {
        return -1;
    }

    ZeroMemory(&entry, sizeof(entry));
    entry.dwSize = sizeof(entry);
    if (Process32First(snapshot, &entry)) {
        do {
            if (entry.th32ProcessID == pid) {
                found = 1;
                break;
            }
        } while (Process32Next(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return found;
}

static void print_usage_error(const char *message) {
    fputs("{\"tool\":\"win32-rpm\",\"status\":\"usage_error\",\"error\":", stdout);
    json_string(stdout, message);
    fputs("}\n", stdout);
}

int main(int argc, char **argv) {
    DWORD pid = 0;
    ReadSpec reads[32];
    int read_count = 0;
    int process_found = 0;
    HANDLE process = NULL;
    DWORD open_error = 0;
    unsigned long repeat = 1;      /* --repeat N: N samples, one JSON line each */
    unsigned long interval_ms = 0; /* --interval-ms M: Sleep between samples */
    LARGE_INTEGER qpc_frequency;

    ZeroMemory(reads, sizeof(reads));
    QueryPerformanceFrequency(&qpc_frequency);

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--pid") == 0) {
            char *end = NULL;
            unsigned long parsed = 0;
            if (i + 1 >= argc) {
                print_usage_error("missing value for --pid");
                return 2;
            }
            parsed = strtoul(argv[++i], &end, 10);
            if (end == NULL || *end != '\0' || parsed == 0 || parsed > 0xffffffffUL) {
                print_usage_error("invalid --pid value");
                return 2;
            }
            pid = (DWORD)parsed;
        } else if (strcmp(argv[i], "--read-u32") == 0) {
            if (i + 1 >= argc) {
                print_usage_error("missing value for --read-u32");
                return 2;
            }
            if (read_count >= (int)(sizeof(reads) / sizeof(reads[0]))) {
                print_usage_error("too many --read-u32 values");
                return 2;
            }
            if (!parse_read_u32(argv[++i], &reads[read_count])) {
                print_usage_error("invalid --read-u32 value, expected name=0xADDR");
                return 2;
            }
            read_count++;
        } else if (strcmp(argv[i], "--read-bytes") == 0) {
            if (i + 1 >= argc) {
                print_usage_error("missing value for --read-bytes");
                return 2;
            }
            if (read_count >= (int)(sizeof(reads) / sizeof(reads[0]))) {
                print_usage_error("too many reads");
                return 2;
            }
            if (!parse_read_bytes(argv[++i], &reads[read_count])) {
                print_usage_error("invalid --read-bytes value, expected name=0xADDR:0xLEN (LEN <= 0x40000)");
                return 2;
            }
            read_count++;
        } else if (strcmp(argv[i], "--repeat") == 0) {
            char *end = NULL;
            if (i + 1 >= argc) {
                print_usage_error("missing value for --repeat");
                return 2;
            }
            repeat = strtoul(argv[++i], &end, 10);
            if (end == NULL || *end != '\0' || repeat == 0 || repeat > 100000UL) {
                print_usage_error("invalid --repeat value, expected 1..100000");
                return 2;
            }
        } else if (strcmp(argv[i], "--interval-ms") == 0) {
            char *end = NULL;
            if (i + 1 >= argc) {
                print_usage_error("missing value for --interval-ms");
                return 2;
            }
            interval_ms = strtoul(argv[++i], &end, 10);
            if (end == NULL || *end != '\0' || interval_ms > 60000UL) {
                print_usage_error("invalid --interval-ms value, expected 0..60000");
                return 2;
            }
        } else {
            print_usage_error("unknown argument");
            return 2;
        }
    }

    if (pid == 0) {
        print_usage_error("missing --pid");
        return 2;
    }
    if (read_count == 0) {
        print_usage_error("missing --read-u32 or --read-bytes");
        return 2;
    }

    process_found = process_exists(pid);
    if (process_found == 0) {
        printf("{\"tool\":\"win32-rpm\",\"status\":\"process_not_found\",\"pid\":%lu}\n", (unsigned long)pid);
        return 3;
    }
    if (process_found < 0) {
        DWORD error = GetLastError();
        printf("{\"tool\":\"win32-rpm\",\"status\":\"snapshot_failed\",\"pid\":%lu,\"error_code\":%lu}\n",
               (unsigned long)pid,
               (unsigned long)error);
        return 3;
    }

    process = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (process == NULL) {
        open_error = GetLastError();
        printf("{\"tool\":\"win32-rpm\",\"status\":\"open_process_failed\",\"pid\":%lu,\"error_code\":%lu}\n",
               (unsigned long)pid,
               (unsigned long)open_error);
        return 4;
    }

    for (unsigned long sample = 0; sample < repeat; ++sample) {
    if (sample > 0 && interval_ms > 0) {
        Sleep((DWORD)interval_ms);
    }
    fputs("{\"tool\":\"win32-rpm\",\"status\":\"ok\",\"pid\":", stdout);
    fprintf(stdout, "%lu", (unsigned long)pid);
    if (repeat > 1) {
        /* Host clocks for rate measurements: GetTickCount is the clock the game paces on. */
        LARGE_INTEGER qpc_now;
        QueryPerformanceCounter(&qpc_now);
        fprintf(stdout, ",\"sample\":%lu,\"tick_ms\":%lu,\"qpc_us\":%llu",
                sample,
                (unsigned long)GetTickCount(),
                (unsigned long long)(qpc_now.QuadPart * 1000000LL / qpc_frequency.QuadPart));
    }
    fputs(",\"reads\":[", stdout);
    for (int i = 0; i < read_count; ++i) {
        const char *name_end = strchr(reads[i].name, '=');
        uint32_t value = 0;
        SIZE_T bytes_read = 0;
        BOOL ok;

        if (i > 0) {
            fputc(',', stdout);
        }
        fputs("{\"name\":", stdout);
        fputc('"', stdout);
        fwrite(reads[i].name, 1, (size_t)(name_end - reads[i].name), stdout);
        fputc('"', stdout);
        if (reads[i].length != 0) {
            unsigned char *buffer = (unsigned char *)malloc(reads[i].length);
            if (buffer == NULL) {
                fprintf(stdout, ",\"address\":\"0x%lx\",\"size\":%lu,\"status\":\"out_of_memory\"}", (unsigned long)reads[i].address, (unsigned long)reads[i].length);
                continue;
            }
            ok = ReadProcessMemory(process, (LPCVOID)reads[i].address, buffer, reads[i].length, &bytes_read);
            fprintf(stdout, ",\"address\":\"0x%lx\",\"size\":%lu", (unsigned long)reads[i].address, (unsigned long)reads[i].length);
            if (ok && bytes_read == reads[i].length) {
                fputs(",\"status\":\"ok\",\"hex\":\"", stdout);
                for (SIZE_T k = 0; k < reads[i].length; ++k) {
                    fprintf(stdout, "%02x", buffer[k]);
                }
                fputc('"', stdout);
            } else {
                DWORD error = GetLastError();
                fprintf(stdout, ",\"status\":\"read_failed\",\"error_code\":%lu,\"bytes_read\":%lu", (unsigned long)error, (unsigned long)bytes_read);
            }
            free(buffer);
            fputc('}', stdout);
            continue;
        }
        ok = ReadProcessMemory(
            process,
            (LPCVOID)reads[i].address,
            &value,
            sizeof(value),
            &bytes_read
        );
        fprintf(stdout, ",\"address\":\"0x%lx\",\"size\":\"u32\"", (unsigned long)reads[i].address);
        if (ok && bytes_read == sizeof(value)) {
            fprintf(stdout, ",\"status\":\"ok\",\"value_u32_hex\":\"0x%08lx\"", (unsigned long)value);
        } else {
            DWORD error = GetLastError();
            fprintf(stdout,
                    ",\"status\":\"read_failed\",\"error_code\":%lu,\"bytes_read\":%lu",
                    (unsigned long)error,
                    (unsigned long)bytes_read);
        }
        fputc('}', stdout);
    }
    fputs("]}\n", stdout);
    fflush(stdout);
    }

    CloseHandle(process);
    return 0;
}
