#pragma once
#include <windows.h>
#include "kelpie/peer_approval.h"

namespace kelpie::windows {
void PollComputerApproval(PeerApprovalQueue& approvals, HWND owner);
void ShowTrustedComputers(HWND owner);
}
