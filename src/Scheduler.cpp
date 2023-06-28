#include "Scheduler.h"
#include "meta_utils.h"

Scheduler g_Scheduler;
unsigned int g_schedule_id = 1;

void Scheduler::Think() {
    float now = g_engfuncs.pfnTime();

    for (int i = 0; i < functions.size(); i++) {
        if (now - functions[i].lastCall < functions[i].delay) {
            continue;
        }

        // not using a local reference to functions[i] because 'functions' might be updated
        // as part of this func() call
        functions[i].func();
        functions[i].lastCall = now;
        functions[i].callCount++;

        if (functions[i].maxCalls >= 0 && functions[i].callCount >= functions[i].maxCalls) {
            functions.erase(functions.begin() + i);
            i--;
        }
    }
}

void Scheduler::RemoveTimer(ScheduledFunction sched) {
    for (int i = 0; i < functions.size(); i++) {
        if (functions[i].scheduleId == sched.scheduleId) {
            functions.erase(functions.begin() + i);
            return;
        }
    }
}

bool ScheduledFunction::HasBeenRemoved() {
    for (int i = 0; i < g_Scheduler.functions.size(); i++) {
        if (g_Scheduler.functions[i].scheduleId == scheduleId) {
            return false;
        }
    }
    return true;
}