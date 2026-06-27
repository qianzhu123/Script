const fs = require('fs');

const lines = [];

lines.push('');
lines.push('$pkgJson = Get-Content (Join-Path $projectPath "package.json") | ConvertFrom-Json');
lines.push('');
lines.push('if ($pkgJson.dependencies.animejs) {');
lines.push("    Write-Host \"\"");
lines.push("    Write-Host \"📦 animejs 版本: $($pkgJson.dependencies.animejs)\" -ForegroundColor Cyan");
lines.push("    Write-Host \"\"");
lines.push("    Write-Host \"使用方法:\" -ForegroundColor Yellow");
lines.push("    Write-Host \"  import { animate, stagger, timeline } from 'animejs';\" -ForegroundColor White");
lines.push("    Write-Host \"\"");
lines.push("    Write-Host \"  animate('.box', { x: 300, duration: 800 });\" -ForegroundColor Gray");
lines.push('} else {');
lines.push("    Write-Host \"[警告] 未在 package.json 中找到 animejs 依赖\" -ForegroundColor Yellow");
lines.push('}');
lines.push('');
lines.push('pause');

fs.appendFileSync(
  'D:/code/myweb/daily/ps1/animejs-installer.ps1',
  '\r\n' + lines.join('\r\n'),
  'utf8'
);
console.log('Part 5 done, ' + lines.length + ' lines appended');