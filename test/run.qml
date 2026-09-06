import QtQuick
import "plug" as Plug
Item { width: 10; height: 10
  Plug.Service { id: svc; shell: ({ shellConfig: { idle: { screensaver: 150 } } }) }
  Timer { interval: 400; running: true; onTriggered: {
    svc.applyStatus({ ready: true, on: true, beat: 7.83, base: 136, scene: "Sit", clips: [], clipDir: "/tmp/svc/clips" })
    svc.applyStatus({ plate: { count: 2, n: [2, 0], f: [40, 69], lut: "data:image/bmp;base64,Qk1GAAAAAAAAADYAAAAoAAAAAgAAAAIAAAABABgAAAAAABAAAAATCwAAEwsAAAAAAAAAAAAAAAD/AAD/AAD/AAAAAAD/AAAAAAA=" } })
    svc.applyStatus({ a: [0.5, 0.4, 0.3, 0.2, 136, 143.8, 1], s: [1, 2, 3], p: [50, 10] })
    svc.showWindow(); svc.setScene("Rest") } }
  Timer { interval: 1500; running: true; onTriggered: { console.log("service ran; windowOpen", svc.windowOpen, "plate", !!svc.plateMsg, "amps", svc.modeAmps.length); Qt.quit() } }
}
