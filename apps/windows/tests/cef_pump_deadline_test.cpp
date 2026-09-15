#include "cef_pump_deadline.h"
using kelpie::windows::CeftPumpDeadline;
int main(){CeftPumpDeadline d;d.Schedule(10,50);d.Schedule(10,20);if(!d.due_ms()||*d.due_ms()!=30)return 1;if(d.ConsumeIfDue(29)||!d.ConsumeIfDue(30))return 2;d.Schedule(40,0);return d.ConsumeIfDue(40)?0:3;}
