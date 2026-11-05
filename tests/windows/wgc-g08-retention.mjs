// Match c149 shared verifier retention: keep pre-first-marker calibration
// candidates and at most the newest 100 non-calibration ROI buffers.
export function createG08Retention(){
 const samples=[];let calibrationStart,markerSeen=false;
 return {samples,push(sample){
  if(calibrationStart===undefined&&sample.pointer)calibrationStart=sample.timeMs;
  sample.calibrationCandidate=calibrationStart!==undefined&&!markerSeen&&sample.timeMs<=calibrationStart+8000;
  if(sample.marker.alpha>.2)markerSeen=true;
  samples.push(sample);const old=samples[samples.length-101];if(old&&!old.calibrationCandidate)delete old.marker.roi;
 }};
}
