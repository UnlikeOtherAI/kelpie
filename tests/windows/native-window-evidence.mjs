// A global red-pixel total is not evidence: ClearType fringes can satisfy it.
// Only the exact native presentation window with verified spatial/radius
// component evidence can certify this synthetic fixture's marker.
export function nativeMarkerVerified(images) {
  return images.some(image=>{
    const region=image.markerRegion;
    return image.className==="KelpieScriptPresentation" &&
      image.status==="pixels-captured" && region?.verified===true &&
      Number.isFinite(region.minimumPixels) && region.minimumPixels>=100 &&
      Number.isFinite(region.connectedPixels) && region.connectedPixels>=region.minimumPixels &&
      region.centerWithinExpected===true && region.radiusWithinExpected===true;
  });
}
