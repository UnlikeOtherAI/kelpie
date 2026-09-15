#include "owner_task_queue.h"
using kelpie::windows::OwnerTaskQueue;
int main(){OwnerTaskQueue q;int called=0;auto a=q.Enqueue([&]{++called;});q.RunOne();if(!q.Wait(a,std::chrono::milliseconds(1))||called!=1)return 1;auto b=q.Enqueue([&]{++called;});q.Cancel();return q.Wait(b,std::chrono::milliseconds(1))?2:0;}
