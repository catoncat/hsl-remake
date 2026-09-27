#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* Bounded, out-of-process Win32 input experiment for the user's hsl01.exe.
 * No hooks, memory writes, saved-game edits, or PostMessage fake input.
 * Output confirms injection only; a subsequent screenshot verifies behavior.
 */
static DWORD game_pid;
static HWND game_window;
static int window_count;

static int fail(const char *reason, int status) {
    fprintf(stderr, "{\"status\":\"error\",\"reason\":\"%s\",\"win32_error\":%lu}\n", reason, (unsigned long)GetLastError());
    return status;
}

static BOOL CALLBACK collect(HWND window, LPARAM unused) {
    DWORD pid = 0;
    RECT rect;
    (void)unused;
    GetWindowThreadProcessId(window, &pid);
    if (pid == game_pid && IsWindowVisible(window) && GetClientRect(window, &rect)
        && rect.right >= 600 && rect.bottom >= 450) {
        game_window = window;
        window_count++;
    }
    return TRUE;
}

static int find_game(void) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32 entry = {0};
    int count = 0;
    if (snapshot == INVALID_HANDLE_VALUE) return fail("process_snapshot_failed", 3);
    entry.dwSize = sizeof(entry);
    if (Process32First(snapshot, &entry)) do {
        if (!_stricmp(entry.szExeFile, "hsl01.exe")) { game_pid = entry.th32ProcessID; count++; }
    } while (Process32Next(snapshot, &entry));
    CloseHandle(snapshot);
    if (count != 1) return fail(count ? "ambiguous_game_process" : "game_not_running", 3);
    EnumWindows(collect, 0);
    if (window_count != 1) return fail(window_count ? "ambiguous_game_window" : "game_window_not_found", 3);
    return 0;
}

static void inspect(const char *status) {
    RECT client = {0}, outer = {0};
    POINT origin = {0}, cursor = {0};
    GetClientRect(game_window, &client);
    GetWindowRect(game_window, &outer);
    ClientToScreen(game_window, &origin);
    GetCursorPos(&cursor);
    printf("{\"status\":\"%s\",\"pid\":%lu,\"hwnd\":\"%p\",\"foreground\":%s,\"client\":[%ld,%ld],\"origin\":[%ld,%ld],\"window\":[%ld,%ld,%ld,%ld],\"cursor\":[%ld,%ld]}\n",
        status, (unsigned long)game_pid, (void *)game_window,
        GetForegroundWindow() == game_window ? "true" : "false", client.right, client.bottom,
        origin.x, origin.y, outer.left, outer.top, outer.right, outer.bottom, cursor.x, cursor.y);
}

static int number(const char *text, long max, long *value) {
    char *end = NULL;
    errno = 0;
    *value = strtol(text, &end, 10);
    return !errno && end != text && !*end && *value >= 0 && *value <= max;
}

static WORD key(const char *name) {
    if (!strcmp(name, "snapshot")) return VK_SNAPSHOT;
    if (!strcmp(name, "space")) return VK_SPACE;
    if (!strcmp(name, "enter")) return VK_RETURN;
    if (!strcmp(name, "escape")) return VK_ESCAPE;
    if (!strcmp(name, "left")) return VK_LEFT;
    if (!strcmp(name, "right")) return VK_RIGHT;
    if (!strcmp(name, "up")) return VK_UP;
    if (!strcmp(name, "down")) return VK_DOWN;
    if (!strcmp(name, "tab")) return VK_TAB;
    return 0;
}

static int send_one(INPUT *input) {
    return SendInput(1, input, sizeof(*input)) == 1;
}

int main(int argc, char **argv) {
    long x = 0, y = 0, hold = 160;
    WORD vk = 0;
    int mode = 0;
    int focus_before_input = argc > 1 && !strcmp(argv[1], "--focus");
    if (focus_before_input) { argc--; argv++; }
    if (argc == 2 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "help"))) {
        puts("hsl_win32_control.exe inspect | focus | place X Y | key snapshot|space|enter|escape|left|right|up|down|tab [20..1000ms] | move X Y | click X Y [20..1000ms] | rclick X Y [20..1000ms]");
        puts("place X Y: move the game window's top-left to desktop X,Y (0..3999; no resize, no input) - for a window left on a disconnected display.");
        puts("Coordinates: 640x480 client space. Optional --focus explicitly focuses the game in this same helper process before input. May move the physical pointer. No success claim beyond input injection.");
        return 0;
    }
    if (argc == 2 && !strcmp(argv[1], "inspect")) mode = 1;
    else if (argc == 2 && !strcmp(argv[1], "focus")) mode = 2;
    else if (argc == 4 && !strcmp(argv[1], "place")) {
        mode = 7;
        if (!number(argv[2], 3999, &x) || !number(argv[3], 3999, &y)) return fail("invalid_coordinates", 2);
    }
    else if ((argc == 3 || argc == 4) && !strcmp(argv[1], "key") && (vk = key(argv[2]))) {
        mode = 3;
        if (argc == 4 && (!number(argv[3], 1000, &hold) || hold < 20)) return fail("invalid_hold", 2);
    } else if ((argc == 4 || argc == 5) &&
        (!strcmp(argv[1], "move") || !strcmp(argv[1], "click") || !strcmp(argv[1], "rclick"))) {
        mode = !strcmp(argv[1], "move") ? 4 : (!strcmp(argv[1], "click") ? 5 : 6);
        if (!number(argv[2], 639, &x) || !number(argv[3], 479, &y)) return fail("invalid_coordinates", 2);
        if (argc == 5 && (mode == 4 || !number(argv[4], 1000, &hold) || hold < 20)) return fail("invalid_hold", 2);
    }
    if (!mode) return fail("invalid_arguments_use_help", 2);
    int found = find_game();
    if (found) return found;
    if (focus_before_input && mode >= 3 && GetForegroundWindow() != game_window) {
        if (IsIconic(game_window)) ShowWindow(game_window, SW_RESTORE);
        SetForegroundWindow(game_window);
        Sleep(500);
    }
    if (mode == 1) { inspect("observed"); return 0; }
    if (mode == 7) {
        /* Wine keeps the window where the last session left it; when that display is gone the
         * game surface is off-screen and every click lands on nothing. */
        if (!SetWindowPos(game_window, NULL, (int)x, (int)y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
            return fail("place_failed", 4);
        inspect("placed"); return 0;
    }
    if (mode == 2) {
        ShowWindow(game_window, SW_RESTORE);
        SetForegroundWindow(game_window);
        Sleep(200);
        if (GetForegroundWindow() != game_window) return fail("focus_failed", 4);
        inspect("focused"); return 0;
    }
    if (GetForegroundWindow() != game_window) return fail("game_not_foreground", 4);
    INPUT input = {0};
    if (mode == 3) {
        input.type = INPUT_KEYBOARD;
        input.ki.wScan = (WORD)MapVirtualKeyA(vk, MAPVK_VK_TO_VSC);
        input.ki.dwFlags = KEYEVENTF_SCANCODE;
        if (vk >= VK_LEFT && vk <= VK_DOWN) input.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
        if (vk == VK_SNAPSHOT) { input.ki.wVk = vk; input.ki.wScan = 0; input.ki.dwFlags = 0; }
        if (!send_one(&input)) return fail("key_down_failed", 5);
        Sleep((DWORD)hold);
        input.ki.dwFlags |= KEYEVENTF_KEYUP;
        if (!send_one(&input)) { send_one(&input); return fail("key_up_failed", 5); }
    } else {
        RECT client;
        POINT point;
        if (!GetClientRect(game_window, &client) || client.right <= 0 || client.bottom <= 0) return fail("invalid_client", 4);
        point.x = x * client.right / 640;
        point.y = y * client.bottom / 480;
        if (!ClientToScreen(game_window, &point)) return fail("coordinate_mapping_failed", 4);
        int left = GetSystemMetrics(SM_XVIRTUALSCREEN), top = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int width = GetSystemMetrics(SM_CXVIRTUALSCREEN), height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        if (width < 2 || height < 2) return fail("invalid_desktop", 4);
        input.type = INPUT_MOUSE;
        input.mi.dx = (LONG)((double)(point.x - left) * 65535.0 / (width - 1));
        input.mi.dy = (LONG)((double)(point.y - top) * 65535.0 / (height - 1));
        input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
        if (!send_one(&input)) return fail("mouse_move_failed", 5);
        Sleep(180);
        if (mode != 4) {
            if (GetForegroundWindow() != game_window) return fail("focus_lost_before_click", 4);
            ZeroMemory(&input, sizeof(input));
            input.type = INPUT_MOUSE;
            input.mi.dwFlags = mode == 5 ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_RIGHTDOWN;
            if (!send_one(&input)) return fail("button_down_failed", 5);
            Sleep((DWORD)hold);
            input.mi.dwFlags = mode == 5 ? MOUSEEVENTF_LEFTUP : MOUSEEVENTF_RIGHTUP;
            if (!send_one(&input)) { send_one(&input); return fail("button_up_failed", 5); }
        }
    }
    Sleep(200);
    inspect("input_injected_not_behavior_verified");
    return 0;
}
