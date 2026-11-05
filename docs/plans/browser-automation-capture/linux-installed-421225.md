# Linux installed candidate: run 42122562425

The hosted candidate used source `455d1923677d7b143bbb0e13719546827af221e4`.
The run is [42122562425](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42122562425).
These are installed-container results, not physical GNOME verification.

## Ubuntu 22.04

The DEB build and installed verification passed. The package SHA-256 was
`ce87591301192a70c980b7c55cb155254a9dd8bf360210ff5b93c907a785d74a`;
the installed ELF was
`dfb134b938d4c4fbf117a27963e9023bf4e00ddb3194ad35323841469f1ed0c5`,
and its CEF library was
`d6bee514adcc2ea2d6e8a450939f7a09da746f1e9b7c8275b9be61b60cd26d99`.
The CLI package was
`e4020d1600a0a9701bcfc32047aaaa238c576b58a86f1915fface71fa0ca7c8d`;
Node 22.14.0 archive SHA-256 was
`69b09dba5c8dcb05c4e4273a4340db1005abeafe3927efda2bc5b249e80437ec`.

The native corpus passed 58/58 checks. All 49 retained artifacts decoded
(24 PNG, 16 GIF, nine MP4), and the strict continuous marker check had no
violations. The CLI passed five checks and ten observation checks, with public
alias stop and readiness cleanup. FFmpeg was 4.4.2, GStreamer 1.20.3 and
OpenH264 2.2.0. This run did not request the independent terminal-IDR check.

Receipt SHA-256 values: native report
`775caa828ad29c814d58d92fc0f27e8a056ee565f32403db70c52dfbf401a303`;
all-frame decoder
`c05589e2cf7b760e46b150073de7f84ad097f96cf395e32d83f51f37804cd812`;
marker
`4a5a2cdfc3f47845b459088e7d35b293c292055d0c7b469809d9df0332563b38`;
CLI
`f0913d884d9a9f5dd77a9966d906c7e979f2c54c197f2e1f4701b5337c1ce24a`.

## Fedora 44

The RPM build and installed verification passed. The RPM SHA-256 was
`e62df3aa575ccb74a1faa31dc537a66a5350c256c0e8f97d4c501c3fac0d637c`;
the installed ELF was
`15c6d43ddcc8f30d459dcc76002acee5516e32855047185e184d48af613b3f00`.
The CEF library, CLI package and Node archive matched the Ubuntu hashes above.

The native corpus passed 58/58 checks. All 47 retained artifacts decoded
(23 PNG, 15 GIF, nine MP4), and the strict continuous marker check had no
violations. The CLI passed five checks and ten observation checks, with public
alias stop and readiness cleanup. FFmpeg was 8.1.3, GStreamer 1.28.8 and
OpenH264 2.6.0. This run did not request the independent terminal-IDR check.

Receipt SHA-256 values: native report
`3893765c010a58c885e9e515415b686fa8b4b5cf3b668d411009be46c5f832be`;
all-frame decoder
`87e3cb2c044f77f15377a0a13a54b9ca703db3c506e3d01a37b7e5fe28588c6c`;
marker
`7935742cea491e82acb942f9f6f4b80d050352f5fe5dfc1b5952836016b94d7a`;
CLI
`7aec6f6bdf38337ba6cfdc22a25cbd2ae6e2fc4df5c312a18c51f4179d4cc995`.
