// Observe immediately without replacing the original rejecting Promise.
export function observeInFlight(promise) {
  promise.catch(() => {});
  return promise;
}
export async function awaitBounded(promise, milliseconds) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer=setTimeout(()=>reject(new Error("Owned operation exceeded cleanup bound")),milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}
