import {test} from "node:test";
import assert from "node:assert/strict";
import {selectFfmpegPassthrough} from "./ffmpeg-passthrough.mjs";

test("prefers modern passthrough and accepts legacy vsync",()=>{
 assert.deepEqual(selectFfmpegPassthrough("  -fps_mode[:stream_specifier] set framerate mode\n -vsync legacy"),
  ["-fps_mode","passthrough"]);
 assert.deepEqual(selectFfmpegPassthrough("  -vsync method set video sync"),["-vsync","0"]);
});
test("refuses missing or misleading options",()=>{
 assert.throws(()=>selectFfmpegPassthrough(" -fps_mode_extra ignored -vsync_extra ignored"),/FFMPEG_PASSTHROUGH_UNAVAILABLE/);
 assert.throws(()=>selectFfmpegPassthrough(""),/FFMPEG_PASSTHROUGH_UNAVAILABLE/);
});
