// Test-only timestamped stills from the already isolated, ownership-checked compositor.
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { captureIsolatedWayland } from "./wayland-capture.mjs";

export async function captureIsolatedTimeline(options) {
  const output=join(options.output,"isolated-wayland-timeline");
  await mkdir(output,{mode:0o700});
  const origin=process.hrtime.bigint(), samples=[];
  try {
    while(samples.length<24 && Number(process.hrtime.bigint()-origin)/1e6<2500) {
      const directory=join(output,String(samples.length).padStart(3,"0"));
      await mkdir(directory,{mode:0o700});
      const begin=process.hrtime.bigint();
      const image=await captureIsolatedWayland({...options,output:directory});
      const end=process.hrtime.bigint();
      samples.push({startNs:begin.toString(),endNs:end.toString(),file:image.file,
        sha256:image.sha256,width:image.width,height:image.height,views:image.views});
    }
    return {scope:"ISOLATED_WAYLAND",originNs:origin.toString(),samples};
  } finally {
    await writeFile(join(output,"timeline.json"),JSON.stringify({scope:"ISOLATED_WAYLAND",originNs:origin.toString(),samples},null,2));
  }
}
