export function applyG08MotionProfile(workflow, profile) {
 if (!["dense","fast","default"].includes(profile)) throw new Error("Unknown G08 motion profile");
 if (profile === "default") delete workflow.pointer.durationMs;
 else workflow.pointer.durationMs = profile === "dense" ? 2400 : 350;
 return workflow;
}
