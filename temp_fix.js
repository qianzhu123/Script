const fs = require('fs');
let c = fs.readFileSync('D:/code/myweb/daily/ps1/install_animejs.ps1', 'utf8');
c = c.replace(/<powershell_script>\r?\n?/g, '').replace(/<\/powershell_script>/g, '');
fs.writeFileSync('D:/code/myweb/daily/ps1/install_animejs.ps1', c);
console.log('done');