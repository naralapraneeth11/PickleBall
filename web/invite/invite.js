// Invite links: https://<site>/invite/?t=<token> opens the app, or shows the
// code to type in.
document.addEventListener("DOMContentLoaded", function () {
  "use strict";
  var token = new URLSearchParams(location.search).get("t") || "";
  var open = document.getElementById("open");
  if (/^[0-9a-f]{24}$/.test(token)) {
    open.href = "pickleball://invite/" + token;
    document.getElementById("code").textContent = token;
    document.getElementById("codeBox").hidden = false;
  } else {
    open.hidden = true;
  }
});
