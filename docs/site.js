/* Open Swim Workout site — tab switching + copy buttons. No dependencies. */
(function () {
  "use strict";
  document.documentElement.classList.add("js");

  // ----- Tabs -----
  document.querySelectorAll("[data-tabs]").forEach(function (tabs) {
    var buttons = Array.prototype.slice.call(tabs.querySelectorAll("[role=tab]"));
    var panels = buttons.map(function (b) {
      return document.getElementById(b.getAttribute("aria-controls"));
    });

    function select(i) {
      buttons.forEach(function (b, j) {
        b.setAttribute("aria-selected", i === j ? "true" : "false");
        b.tabIndex = i === j ? 0 : -1;
        if (panels[j]) panels[j].hidden = i !== j;
      });
    }

    buttons.forEach(function (b, i) {
      b.addEventListener("click", function () { select(i); });
      b.addEventListener("keydown", function (e) {
        var d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        if (!d) return;
        e.preventDefault();
        var n = (i + d + buttons.length) % buttons.length;
        select(n);
        buttons[n].focus();
      });
    });

    select(0);
  });

  // ----- Copy buttons -----
  document.querySelectorAll(".copy-btn").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var block = btn.closest(".codeblock");
      var pre = block && block.querySelector("pre");
      if (!pre || !navigator.clipboard) return;
      navigator.clipboard.writeText(pre.textContent.trim() + "\n").then(function () {
        var old = btn.textContent;
        btn.textContent = "Copied";
        setTimeout(function () { btn.textContent = old; }, 1400);
      });
    });
  });
})();
