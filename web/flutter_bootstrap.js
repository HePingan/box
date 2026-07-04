// Custom flutter_bootstrap.js
// Fix: In headless Chrome environments, CanvasKit/WebGL initialization via
// SwiftShader can deadlock, causing didCreateEngineInitializer to never fire.
// Swap build order so the empty (HTML renderer) build is preferred — no WebGL needed.
{{flutter_js}}
{{flutter_build_config}}
(function() {
  var builds = _flutter.buildConfig.builds;
  if (!builds || builds.length < 2) return;
  var canvaskitIdx = -1, emptyIdx = -1;
  for (var i = 0; i < builds.length; i++) {
    if (builds[i].renderer === 'canvaskit') canvaskitIdx = i;
    if (!builds[i].renderer && !builds[i].compileTarget) emptyIdx = i;
  }
  if (canvaskitIdx >= 0 && emptyIdx >= 0 && emptyIdx > canvaskitIdx) {
    var empty = builds.splice(emptyIdx, 1)[0];
    builds.unshift(empty);
  }
})();
_flutter.loader.load({});
