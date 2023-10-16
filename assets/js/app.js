// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// TODO: Allow loading game-specific hooks from separate files instead of all of them all at once.
let Hooks = {}
Hooks.MinesweeperFlag = {
  mounted() {
    this.el.addEventListener("contextmenu", e => {
      e.preventDefault()
      this.pushEvent("flag", {x: this.el.getAttribute("phx-value-x"), y: this.el.getAttribute("phx-value-y")}, (reply, ref) => {})
      return false;
    })
  }
}

Hooks.LightCyclesDraw = {
  mounted() {
    this.handleEvent("draw", ({players}) => {
      let ctx = this.el.getContext("2d")
      ctx.clearRect(0, 0, this.el.width, this.el.height)
      ctx.lineWidth = 5;

      for(const [id, player] of Object.entries(players)) {
        ctx.strokeStyle = player.color
        ctx.beginPath();
        start = player.points.shift();
        ctx.moveTo(...start)
        player.points.forEach((point) => {
          ctx.lineTo(...point)
        })
        ctx.stroke();
      }
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

