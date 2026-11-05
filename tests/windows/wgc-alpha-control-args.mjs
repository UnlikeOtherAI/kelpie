import {win32} from "node:path";
export function alphaControlWgcArgs(identity,executable,output){
 return [String(identity.pid),win32.normalize(executable),identity.startFileTime,identity.hwnd,output];
}
