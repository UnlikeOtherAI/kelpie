export function createG08WitnessLog(){
 const rows=[];let done=null,invalid=false;
 return {
  accept(line){
   if(!line.startsWith("KELPIE_TEST_G08_ROI_"))return;
   const row=/^KELPIE_TEST_G08_ROI_ROW (\d{1,3}) (\d{1,12}) ([a-f0-9]{64})$/.exec(line);
   const end=/^KELPIE_TEST_G08_ROI_DONE (\d{1,3})$/.exec(line);
   if(row&&done===null&&rows.length<800&&Number(row[1])===rows.length)
    rows.push({frameIndex:Number(row[1]),pts100ns:Number(row[2]),roiSha256:row[3]});
   else if(end&&done===null)done=Number(end[1]);else invalid=true;
  },
  finish(){return !invalid&&done===rows.length&&rows.length>0?rows.slice():null;},
 };
}
