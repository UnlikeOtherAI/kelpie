const LINE=/^KELPIE_CAPTURE_STAGE (\d{1,9}\.\d{3}) (\d{1,9}\.\d{3}) (\d{1,9}\.\d{3}) (\d{1,9}\.\d{3}) (\d{1,9}\.\d{3})$/;
export function parseCaptureStage(line){
 if(line==="KELPIE_CAPTURE_STAGE_TRUNCATED")return {truncated:true};
 const match=LINE.exec(line);if(!match)return null;
 const values=match.slice(1).map(Number);
 if(values.some(value=>!Number.isFinite(value)||value>300000))return null;
 const [elapsedMs,preMs,screenshotMs,postMs,encoderMs]=values;
 return {elapsedMs,preMs,screenshotMs,postMs,encoderMs};
}
