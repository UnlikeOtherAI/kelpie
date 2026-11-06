const BYTES=/^KELPIE_TEST_SCRIPT_PNG_BYTES (\d{1,6}) (\d{1,18}) (\d{1,10})$/;
export function parsePngSpeedBytes(line){
 const match=BYTES.exec(line);if(!match)return null;
 const [count,totalBase64Chars,maxBase64Chars]=match.slice(1).map(Number);
 if(![count,totalBase64Chars,maxBase64Chars].every(Number.isSafeInteger)||count>800||
    maxBase64Chars>totalBase64Chars||(count===0&&(totalBase64Chars!==0||maxBase64Chars!==0)))return null;
 return {count,totalBase64Chars,maxBase64Chars};
}
