import Foundation
import Network

/// The fixture is served by the test runner and stays on the simulator loopback interface.
final class WorkflowLoopbackPage {
    enum Failure: Error { case listener }
    let listener: NWListener
    private let responseDelay: TimeInterval
    private let requestCounter = WorkflowRequestCounter()
    func requestCount(path: String) -> Int { requestCounter.count(path) }
    init(responseDelay: TimeInterval = 0) throws {
        self.responseDelay = responseDelay
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: .any)
    }

    func start() async throws -> String {
        let queue = DispatchQueue(label: "kelpie.ios.workflow.fixture")
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Count 0</title>
        <style>body{background:white;color:black}button{display:block;margin:25vh auto;width:150px;height:80px}</style>
        <meta property="og:site_name" content="Fixture Press">
        <script type="application/ld+json">{"@type":"Article","headline":"Public headline","password":"PRIVATE_LD"}</script>
        <a id="continue" href="/landed">Continue</a><main><article><h2>Alpha</h2><a href="/alpha">Read</a></article><article><h2>Beta</h2></article>
        <input type="password" aria-label="Private input" value="PRIVATE_INPUT" oninput="document.title=this.value">
        <label>Entry <input id="entry" oninput="document.querySelector('#length').textContent=this.value.length"></label><output id="length"></output>
        <div contenteditable>PRIVATE_EDITOR</div></main>
        <button>Submit</button><output id="geometry"></output><script>
        window.count=0;document.querySelector('button').onclick=e=>{
          const r=e.currentTarget.getBoundingClientRect(),x=(Math.max(0,r.left)+Math.min(innerWidth,r.right))/2;
          const y=(Math.max(0,r.top)+Math.min(innerHeight,r.bottom))/2;
          document.querySelector('#geometry').textContent=Math.abs(x-e.clientX)<=1&&Math.abs(y-e.clientY)<=1?'center':'missed';
          document.title='Count '+(++window.count)
        }
        const button=document.querySelector('button');
        if(location.pathname==='/secret-guard'||location.pathname.startsWith('/focus-secret-')||location.pathname.startsWith('/post-input-secret-')){
          document.title='iOS Reflected+Canary! | iOS%20Reflected%2bCanary! | iOS+Reflected%2bCanary%21';
          document.querySelector('input[type=password]').oninput=()=>{document.title='Unexpected edit'};
          const field=document.querySelector('#entry');
          field.oninput=()=>{document.title='Unexpected edit'};
          if(location.pathname==='/focus-secret-password')field.onfocus=()=>{field.type='password'};
          if(location.pathname==='/focus-secret-autocomplete')field.onfocus=()=>{field.autocomplete='current-password'};
          if(location.pathname==='/focus-secret-timeout')field.onfocus=()=>{
            const end=performance.now()+6500;while(performance.now()<end){}
          };
          if(location.pathname.startsWith('/post-input-secret-')){
            let inputs=0,later=0;
            const report=()=>{document.title='Input '+inputs+' Later '+later};
            field.oninput=()=>{
              inputs++;
              if(location.pathname.endsWith('password'))field.type='password';
              else field.autocomplete='current-password';
              report();
            };
            button.onclick=()=>{later++;report()};
          }
        }
        if(location.pathname==='/scroll'){
          document.documentElement.style.background='#D0D0D0';document.body.style='margin:0;background:#D0D0D0;height:300vh;position:relative';
          document.body.innerHTML='<button id="bottom" style="position:absolute;bottom:12px;left:12px;margin:0">Bottom</button>'
        }
        if(location.pathname==='/motion'){
          document.documentElement.style.background='#606060';document.body.style='margin:0;background:#606060';
          document.body.innerHTML='<button style="appearance:none;position:fixed;left:58vw;top:60vh;transform:translate(-50%,-50%);margin:0;background:#505050;color:#181818;border:0">Track</button>'
          document.querySelector('button').onclick=()=>{document.title='Track clicked'}
        }
        if(location.pathname==='/pinch'){
          document.documentElement.style.background='#606060';
          document.body.style='margin:0;background:#606060;height:100vh;overflow:hidden';
          document.body.innerHTML='<button id="edge" style="position:fixed;margin:0;width:150px;height:80px;appearance:none;background:#505050;color:#181818;border:0">Edge</button><output id="zoom" style="position:absolute;left:0;top:0;color:#181818;font-size:8px"></output><output id="clicked" style="position:absolute;left:0;top:14px;color:#181818;font-size:8px"></output>';
          const edge=document.querySelector('#edge'),metrics=document.querySelector('#zoom');
          let clicks=0;
          const viewport=()=>({scale:visualViewport.scale,x:visualViewport.offsetLeft,y:visualViewport.offsetTop,
            width:visualViewport.width,height:visualViewport.height,layoutWidth:innerWidth,layoutHeight:innerHeight});
          const position=()=>{
            const v=viewport();
            edge.style.left=Math.min(innerWidth-150,v.x+v.width-50)+'px';
            edge.style.top=(v.y+v.height/2-40)+'px';
            metrics.textContent=JSON.stringify({...v,clicks});
          };
          visualViewport.addEventListener('resize',position);visualViewport.addEventListener('scroll',position);
          edge.onclick=e=>{
            const v=viewport(),r=edge.getBoundingClientRect(),left=Math.max(v.x,r.left),right=Math.min(v.x+v.width,r.right);
            const top=Math.max(v.y,r.top),bottom=Math.min(v.y+v.height,r.bottom);
            document.querySelector('#clicked').textContent=JSON.stringify({...v,clickX:e.clientX,clickY:e.clientY,
              expectedX:(left+right)/2,expectedY:(top+bottom)/2,visibleWidth:right-left,buttonWidth:r.width,clicks:++clicks});
            position();
          };
          position();
        }
        if(location.pathname==='/landed'){
          document.body.style.background='#1848D8';document.body.innerHTML='<h1 id="landed">Landed</h1>';document.title='Landed'
        }
        if(location.pathname==='/duplicates'){
          const copy=button.cloneNode(true);copy.style='position:fixed;left:8px;top:8px;margin:0';document.body.append(copy)
        }
        if(location.pathname==='/covered'){
          const cover=document.createElement('div');cover.style='position:fixed;inset:0;z-index:2';document.body.append(cover)
        }
        if(location.pathname==='/replace'){
          button.onpointerdown=()=>{document.title='Pointerdown 1';button.replaceWith(button.cloneNode(true))}
        }
        </script>
        """
        let data = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)".utf8)
        listener.newConnectionHandler = { [responseDelay, requestCounter] connection in
            connection.start(queue: queue)
            Self.readPath(connection, buffered: Data()) { path in
                requestCounter.record(path)
                queue.asyncAfter(deadline: .now() + responseDelay) {
                    connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if let port = listener.port { continuation.resume(returning: port.rawValue) }
                    else { continuation.resume(throwing: Failure.listener) }
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return "http://127.0.0.1:\(port)/workflow"
    }
    private static func readPath(_ connection: NWConnection, buffered: Data, complete: @escaping @Sendable (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, ended, error in
            let accumulated = buffered + (data ?? Data())
            guard accumulated.count <= 16384, error == nil else { connection.cancel(); return }
            if let line = String(data: accumulated, encoding: .utf8)?.components(separatedBy: "\r\n").first,
               accumulated.range(of: Data("\r\n".utf8)) != nil {
                let parts = line.split(separator: " ")
                guard parts.count >= 2, parts[1].hasPrefix("/") else { connection.cancel(); return }
                complete(String(parts[1]))
            } else if ended { connection.cancel() } else { readPath(connection, buffered: accumulated, complete: complete) }
        }
    }

    deinit { listener.cancel() }
}

/// Counts only complete, bounded HTTP request lines; a split TCP read cannot hide a destination load.
private final class WorkflowRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func record(_ path: String) { lock.lock(); defer { lock.unlock() }; counts[path, default: 0] += 1 }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[path, default: 0] }
}
