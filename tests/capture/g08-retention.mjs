// Retain bounded pre-dispatch calibration ROIs and the most recent 100 frames.
export function createG08Retention({warmupCalibration=false,pointerMs=2400,markerMs=3000}={},samples=[]){
 let firstPointer,warmupMarker,calibrationMarkerSeen=false;
 return {samples,push(sample){
  if(firstPointer===undefined&&sample.pointer)firstPointer=sample.timeMs;
  if(warmupCalibration){
   if(warmupMarker===undefined&&firstPointer!==undefined&&
      sample.timeMs>=firstPointer+pointerMs*.65&&sample.marker.alpha>.2)warmupMarker=sample.timeMs;
   const floor=warmupMarker===undefined?Infinity:warmupMarker+markerMs+150;
   sample.calibrationCandidate=!calibrationMarkerSeen&&sample.timeMs>=floor&&sample.timeMs<=floor+8000;
   if(sample.calibrationCandidate&&sample.marker.alpha>.2)calibrationMarkerSeen=true;
  }else{
   sample.calibrationCandidate=firstPointer!==undefined&&!calibrationMarkerSeen&&sample.timeMs<=firstPointer+8000;
   if(sample.marker.alpha>.2)calibrationMarkerSeen=true;
  }
  samples.push(sample);
  const old=samples[samples.length-101];if(old&&!old.calibrationCandidate)delete old.marker.roi;
 }};
}
