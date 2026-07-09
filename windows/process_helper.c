// process_helper.c
// 用法: process_helper.exe "java" "-jar" "path\to\mindustry.jar"
//
// 策略：
//   1. FreeConsole() — 隐藏黑框
//   2. 用 STARTUPINFOEX + PROC_THREAD_ATTRIBUTE_JOB_LIST (空列表)
//      阻止子进程继承调用方的 Job Object
//   3. 打印子进程 PID 到 stdout 后立即退出

#include <windows.h>
#include <stdio.h>

int main() {
    FreeConsole();  // 隐藏黑框

    LPWSTR cmdLine = GetCommandLineW();
    LPWSTR target = cmdLine;

    // 跳过第一个 token（helper 自己的路径）
    if (*target == L'"') {
        target++;
        while (*target && *target != L'"') target++;
        if (*target == L'"') target++;
    } else {
        while (*target && *target != L' ') target++;
    }
    while (*target == L' ') target++;

    if (*target == L'\0') {
        printf("ERR: no command\n");
        return 1;
    }

    // ---- STARTUPINFOEX + 空 JOB_LIST (Win8+) ----
    STARTUPINFOEXW si = { sizeof(si) };
    SIZE_T attrSize = 0;
    HANDLE emptyJob = NULL;

    InitializeProcThreadAttributeList(NULL, 1, 0, &attrSize);
    si.lpAttributeList = (PPROC_THREAD_ATTRIBUTE_LIST)
        HeapAlloc(GetProcessHeap(), 0, attrSize);
    if (si.lpAttributeList == NULL ||
        !InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &attrSize)) {
        printf("ERR: attr init failed %lu\n", GetLastError());
        return 1;
    }

    if (!UpdateProcThreadAttribute(
            si.lpAttributeList, 0,
            PROC_THREAD_ATTRIBUTE_JOB_LIST,
            &emptyJob, sizeof(emptyJob),
            NULL, NULL)) {
        printf("ERR: attr update failed %lu\n", GetLastError());
        return 1;
    }

    PROCESS_INFORMATION pi = { 0 };

    BOOL ok = CreateProcessW(
        NULL, target,
        NULL, NULL, FALSE,
        EXTENDED_STARTUPINFO_PRESENT | DETACHED_PROCESS |
            CREATE_NEW_PROCESS_GROUP | CREATE_BREAKAWAY_FROM_JOB,
        NULL, NULL,
        &si.StartupInfo, &pi
    );

    DeleteProcThreadAttributeList(si.lpAttributeList);
    HeapFree(GetProcessHeap(), 0, si.lpAttributeList);

    if (ok) {
        printf("%lu", pi.dwProcessId);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    } else {
        printf("ERR:%lu", GetLastError());
    }

    return 0;
}
