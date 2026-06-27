param(
  [Parameter(Position = 0)]
  [string]$ProjectDir,

  [switch]$Force,

  [int]$Port = 3010
)

$ErrorActionPreference = "Stop"

function Write-Info {
  param([string]$Message)
  Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
  param([string]$Message)
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Assert-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name was not found. Please install it and try again."
  }
}

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Content
  )

  $parent = Split-Path -Parent $Path
  if ($parent -and (-not (Test-Path $parent))) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-FileIfNeeded {
  param(
    [string]$Path,
    [string]$Content,
    [bool]$Overwrite
  )

  if ((Test-Path $Path) -and (-not $Overwrite)) {
    Write-Warn "Skipped existing file: $Path"
    return
  }

  Write-Utf8NoBom -Path $Path -Content $Content
  Write-Ok "Wrote file: $Path"
}

function Read-JsonNoBom {
  param([string]$Path)

  $text = [System.IO.File]::ReadAllText($Path)
  $text = $text.TrimStart([char]0xFEFF)
  return $text | ConvertFrom-Json
}

if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
  $ProjectDir = Read-Host "Enter the project directory"
}

if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
  throw "Project directory is required."
}

$ProjectDir = [System.IO.Path]::GetFullPath($ProjectDir)

Assert-Command "node"
Assert-Command "npm"

if (-not (Test-Path $ProjectDir)) {
  Write-Info "Creating project directory: $ProjectDir"
  New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null
}

Set-Location $ProjectDir
Write-Info "Working directory: $ProjectDir"

if (-not (Test-Path "package.json")) {
  Write-Info "package.json was not found. Running npm init -y."
  npm init -y
  if ($LASTEXITCODE -ne 0) { throw "npm init failed." }
}

Write-Info "Installing Remotion runtime dependencies."
npm install remotion react react-dom
if ($LASTEXITCODE -ne 0) { throw "npm install runtime dependencies failed." }

Write-Info "Installing Remotion development dependencies."
npm install --save-dev @remotion/cli @remotion/renderer typescript @types/node @types/react @types/react-dom
if ($LASTEXITCODE -ne 0) { throw "npm install development dependencies failed." }

$remotionDir = Join-Path $ProjectDir "remotion"
$publicDir = Join-Path $ProjectDir "public"
$outDir = Join-Path $ProjectDir "out"
New-Item -ItemType Directory -Path $remotionDir -Force | Out-Null
New-Item -ItemType Directory -Path $publicDir -Force | Out-Null
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$indexContent = @'
import {registerRoot} from 'remotion';
import {RemotionRoot} from './Root';

registerRoot(RemotionRoot);
'@

$rootContent = @'
import {Composition} from 'remotion';
import {MyVideo} from './MyVideo';

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="MyVideo"
        component={MyVideo}
        durationInFrames={300}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
'@

$videoContent = @'
import {
  AbsoluteFill,
  Easing,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import type {CSSProperties, FC, ReactNode} from 'react';

const clamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const colors = {
  bg: '#030712',
  text: '#F8FAFC',
  muted: '#CBD5E1',
  cyan: '#22D3EE',
  blue: '#60A5FA',
  violet: '#A78BFA',
  pink: '#F472B6',
  green: '#34D399',
  amber: '#FBBF24',
  panel: 'rgba(15, 23, 42, 0.72)',
  panelStrong: 'rgba(15, 23, 42, 0.90)',
};

const sceneStyle: CSSProperties = {
  overflow: 'hidden',
  color: colors.text,
  fontFamily:
    'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, Arial, sans-serif',
  background:
    'radial-gradient(circle at 18% 20%, rgba(34, 211, 238, 0.22), transparent 28%), radial-gradient(circle at 82% 16%, rgba(167, 139, 250, 0.20), transparent 30%), radial-gradient(circle at 58% 92%, rgba(52, 211, 153, 0.16), transparent 34%), #030712',
};

const lineClamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const appear = (frame: number, start: number, end = start + 20) =>
  interpolate(frame, [start, end], [0, 1], lineClamp);

const disappear = (frame: number, start: number, end = start + 20) =>
  interpolate(frame, [start, end], [1, 0], lineClamp);

const Grid: FC = () => {
  const frame = useCurrentFrame();
  const shift = frame * 0.55;

  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        opacity: 0.55,
        backgroundImage:
          'linear-gradient(rgba(148, 163, 184, 0.10) 1px, transparent 1px), linear-gradient(90deg, rgba(148, 163, 184, 0.10) 1px, transparent 1px)',
        backgroundSize: '72px 72px',
        backgroundPosition: `${shift}px ${shift}px`,
        maskImage:
          'linear-gradient(to bottom, transparent, black 12%, black 76%, transparent)',
      }}
    />
  );
};

const Orb: FC<{
  size: number;
  color: string;
  left: number;
  top: number;
  speed: number;
  delay?: number;
}> = ({size, color, left, top, speed, delay = 0}) => {
  const frame = useCurrentFrame();
  const x = Math.cos((frame + delay) / (speed * 1.25)) * 42;
  const y = Math.sin((frame + delay) / speed) * 34;
  const scale = 0.94 + Math.sin((frame + delay) / 16) * 0.08;

  return (
    <div
      style={{
        position: 'absolute',
        left: left + x,
        top: top + y,
        width: size,
        height: size,
        borderRadius: '50%',
        background: color,
        opacity: 0.18,
        filter: 'blur(3px)',
        transform: `scale(${scale})`,
      }}
    />
  );
};

const Progress: FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const width = interpolate(frame, [0, durationInFrames - 1], [0, 100], clamp);

  return (
    <div
      style={{
        position: 'absolute',
        left: 70,
        right: 70,
        bottom: 42,
        height: 8,
        borderRadius: 999,
        background: 'rgba(255,255,255,0.10)',
        overflow: 'hidden',
        boxShadow: '0 0 0 1px rgba(255,255,255,0.08)',
      }}
    >
      <div
        style={{
          height: '100%',
          width: `${width}%`,
          borderRadius: 999,
          background: `linear-gradient(90deg, ${colors.cyan}, ${colors.violet}, ${colors.green})`,
          boxShadow: `0 0 32px ${colors.cyan}`,
        }}
      />
    </div>
  );
};

const Badge: FC<{children: ReactNode; start: number}> = ({children, start}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: frame - start, fps, from: 0, to: 1, config: {damping: 16}});

  return (
    <div
      style={{
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [26, 0])}px) scale(${interpolate(s, [0, 1], [0.94, 1])})`,
        padding: '14px 24px',
        borderRadius: 999,
        background: 'rgba(255,255,255,0.08)',
        border: '1px solid rgba(255,255,255,0.16)',
        backdropFilter: 'blur(14px)',
        color: colors.muted,
        fontSize: 25,
        letterSpacing: 1.2,
        textTransform: 'uppercase',
      }}
    >
      {children}
    </div>
  );
};

const CodeWindow: FC<{start: number; end: number}> = ({start, end}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enter = spring({frame: frame - start, fps, from: 0, to: 1, config: {damping: 18}});
  const opacity = appear(frame, start, start + 18) * disappear(frame, end - 18, end);

  const lines = [
    ['const frame = useCurrentFrame();', colors.cyan],
    ['const motion = interpolate(frame, ...);', colors.violet],
    ['return <VideoScene data={props} />;', colors.green],
  ];

  return (
    <div
      style={{
        position: 'absolute',
        left: 110,
        top: 236,
        width: 720,
        opacity,
        transform: `translateX(${interpolate(enter, [0, 1], [-90, 0])}px) rotateY(${interpolate(enter, [0, 1], [16, 0])}deg)`,
        borderRadius: 30,
        background: colors.panelStrong,
        border: '1px solid rgba(255,255,255,0.14)',
        overflow: 'hidden',
        boxShadow: '0 45px 120px rgba(0,0,0,0.48)',
      }}
    >
      <div
        style={{
          height: 60,
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          paddingLeft: 24,
          background: 'rgba(255,255,255,0.06)',
        }}
      >
        {[colors.pink, colors.amber, colors.green].map((color) => (
          <div key={color} style={{width: 16, height: 16, borderRadius: '50%', background: color}} />
        ))}
        <div style={{marginLeft: 16, color: colors.muted, fontSize: 22}}>remotion/MyVideo.tsx</div>
      </div>
      <div style={{padding: '34px 38px', fontFamily: 'Consolas, Menlo, monospace', fontSize: 30, lineHeight: 1.75}}>
        {lines.map(([text, color], index) => {
          const o = appear(frame, start + 12 + index * 12, start + 26 + index * 12);
          return (
            <div key={text} style={{opacity: o, color}}>
              <span style={{color: 'rgba(148,163,184,0.7)', marginRight: 22}}>{index + 1}</span>
              {text}
            </div>
          );
        })}
      </div>
    </div>
  );
};

const DataPanel: FC<{start: number; end: number}> = ({start, end}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enter = spring({frame: frame - start, fps, from: 0, to: 1, config: {damping: 20}});
  const opacity = appear(frame, start, start + 18) * disappear(frame, end - 18, end);
  const bars = [78, 52, 92, 67, 84, 44, 72];

  return (
    <div
      style={{
        position: 'absolute',
        right: 110,
        top: 226,
        width: 760,
        height: 440,
        opacity,
        transform: `translateX(${interpolate(enter, [0, 1], [90, 0])}px)`,
        borderRadius: 34,
        background: colors.panel,
        border: '1px solid rgba(255,255,255,0.14)',
        boxShadow: '0 45px 120px rgba(0,0,0,0.40)',
        padding: 34,
      }}
    >
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
        <div>
          <div style={{fontSize: 26, color: colors.muted}}>Dynamic data</div>
          <div style={{fontSize: 56, fontWeight: 900, marginTop: 4}}>Render pipeline</div>
        </div>
        <div
          style={{
            padding: '12px 18px',
            borderRadius: 999,
            color: colors.green,
            background: 'rgba(52,211,153,0.12)',
            border: '1px solid rgba(52,211,153,0.28)',
            fontSize: 22,
            fontWeight: 700,
          }}
        >
          LIVE
        </div>
      </div>

      <div style={{display: 'flex', alignItems: 'end', gap: 22, height: 236, marginTop: 42}}>
        {bars.map((height, index) => {
          const grow = appear(frame, start + 20 + index * 5, start + 44 + index * 5);
          return (
            <div key={index} style={{flex: 1, height: '100%', display: 'flex', alignItems: 'end'}}>
              <div
                style={{
                  width: '100%',
                  height: `${height * grow}%`,
                  borderRadius: '18px 18px 6px 6px',
                  background: `linear-gradient(180deg, ${index % 2 ? colors.violet : colors.cyan}, rgba(96,165,250,0.25))`,
                  boxShadow: `0 0 28px ${index % 2 ? 'rgba(167,139,250,0.35)' : 'rgba(34,211,238,0.35)'}`,
                }}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
};

const FeatureCard: FC<{
  title: string;
  text: string;
  icon: string;
  color: string;
  start: number;
  index: number;
}> = ({title, text, icon, color, start, index}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: frame - start, fps, from: 0, to: 1, config: {damping: 15}});

  return (
    <div
      style={{
        width: 430,
        minHeight: 270,
        padding: 30,
        borderRadius: 34,
        background: 'rgba(15, 23, 42, 0.72)',
        border: '1px solid rgba(255,255,255,0.14)',
        boxShadow: '0 34px 90px rgba(0,0,0,0.36)',
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [58, 0])}px) rotate(${interpolate(s, [0, 1], [index % 2 ? 2 : -2, 0])}deg)`,
      }}
    >
      <div
        style={{
          width: 72,
          height: 72,
          borderRadius: 22,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 36,
          background: `${color}22`,
          border: `1px solid ${color}66`,
          marginBottom: 28,
        }}
      >
        {icon}
      </div>
      <div style={{fontSize: 42, fontWeight: 900, marginBottom: 14}}>{title}</div>
      <div style={{fontSize: 25, lineHeight: 1.35, color: colors.muted}}>{text}</div>
    </div>
  );
};

const Ring: FC<{start: number}> = ({start}) => {
  const frame = useCurrentFrame();
  const t = appear(frame, start, start + 50);
  const spin = frame * 0.9;

  return (
    <div
      style={{
        position: 'absolute',
        right: 150,
        top: 168,
        width: 420,
        height: 420,
        borderRadius: '50%',
        opacity: t * 0.75,
        transform: `rotate(${spin}deg) scale(${interpolate(t, [0, 1], [0.8, 1])})`,
        background: `conic-gradient(from 0deg, ${colors.cyan}, transparent, ${colors.violet}, transparent, ${colors.green}, ${colors.cyan})`,
        maskImage: 'radial-gradient(circle, transparent 57%, black 58%)',
        filter: 'drop-shadow(0 0 30px rgba(34,211,238,0.35))',
      }}
    />
  );
};

const HeroScene: FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const title = spring({frame: frame - 18, fps, from: 0, to: 1, config: {damping: 14}});
  const sceneOut = disappear(frame, 98, 128);

  return (
    <AbsoluteFill style={{opacity: sceneOut}}>
      <div style={{position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center'}}>
        <Badge start={8}>AI Assisted Video Generation</Badge>
        <div
          style={{
            marginTop: 38,
            fontSize: 118,
            lineHeight: 1.02,
            fontWeight: 950,
            letterSpacing: -4,
            transform: `translateY(${interpolate(title, [0, 1], [54, 0])}px) scale(${interpolate(title, [0, 1], [0.92, 1])})`,
            opacity: title,
          }}
        >
          Build videos with
          <br />
          <span
            style={{
              background: `linear-gradient(90deg, ${colors.cyan}, ${colors.violet}, ${colors.pink})`,
              WebkitBackgroundClip: 'text',
              backgroundClip: 'text',
              color: 'transparent',
            }}
          >
            React code
          </span>
        </div>
        <div style={{marginTop: 30, maxWidth: 1050, fontSize: 35, lineHeight: 1.35, color: colors.muted, opacity: appear(frame, 46, 70)}}>
          Generate animated scenes, compose UI-like components, and export everything as a video file.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const WorkflowScene: FC = () => {
  const frame = useCurrentFrame();
  const opacity = appear(frame, 110, 136) * disappear(frame, 206, 230);

  return (
    <AbsoluteFill style={{opacity}}>
      <CodeWindow start={120} end={224} />
      <DataPanel start={142} end={224} />
      <Ring start={128} />
      <div style={{position: 'absolute', left: 120, bottom: 170, fontSize: 34, color: colors.muted, opacity: appear(frame, 174, 198)}}>
        Source files → React frames → Preview → MP4 render
      </div>
    </AbsoluteFill>
  );
};

const FeatureScene: FC = () => {
  const frame = useCurrentFrame();
  const opacity = appear(frame, 218, 244) * disappear(frame, 282, 300);

  return (
    <AbsoluteFill style={{opacity}}>
      <div style={{position: 'absolute', left: 0, right: 0, top: 118, textAlign: 'center'}}>
        <div style={{fontSize: 70, fontWeight: 950}}>What you can do next</div>
        <div style={{fontSize: 30, color: colors.muted, marginTop: 16}}>Edit this file, add assets, and render your own video.</div>
      </div>
      <div style={{position: 'absolute', left: 210, right: 210, top: 340, display: 'flex', gap: 34, justifyContent: 'center'}}>
        <FeatureCard
          start={236}
          index={0}
          icon="⚡"
          color={colors.cyan}
          title="Animate"
          text="Use frame numbers, springs, easing and interpolation for precise motion."
        />
        <FeatureCard
          start={250}
          index={1}
          icon="🧩"
          color={colors.violet}
          title="Compose"
          text="Split your video into reusable React components and scenes."
        />
        <FeatureCard
          start={264}
          index={2}
          icon="🎬"
          color={colors.green}
          title="Render"
          text="Export MP4, still images, GIFs, image sequences or use server rendering."
        />
      </div>
    </AbsoluteFill>
  );
};

export const MyVideo: React.FC = () => {
  const frame = useCurrentFrame();
  const vignette = interpolate(frame, [0, 300], [0.35, 0.62], clamp);
  const sweep = interpolate(frame, [0, 300], [-700, 2300], clamp);

  return (
    <AbsoluteFill style={sceneStyle}>
      <Grid />
      <Orb size={360} color={colors.cyan} left={-70} top={110} speed={32} />
      <Orb size={460} color={colors.violet} left={1540} top={80} speed={38} delay={40} />
      <Orb size={300} color={colors.green} left={760} top={760} speed={34} delay={80} />

      <div
        style={{
          position: 'absolute',
          left: sweep,
          top: -240,
          width: 360,
          height: 1600,
          transform: 'rotate(18deg)',
          background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.12), transparent)',
          filter: 'blur(2px)',
        }}
      />

      <HeroScene />
      <WorkflowScene />
      <FeatureScene />

      <div
        style={{
          position: 'absolute',
          inset: 0,
          pointerEvents: 'none',
          background: `radial-gradient(circle at center, transparent 46%, rgba(0,0,0,${vignette}) 100%)`,
        }}
      />
      <Progress />
    </AbsoluteFill>
  );
};
'@

$tsconfigContent = @'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "noEmit": true,
    "types": ["node", "react", "react-dom"]
  },
  "include": ["remotion/**/*.ts", "remotion/**/*.tsx"]
}
'@

Write-FileIfNeeded -Path (Join-Path $remotionDir "index.ts") -Content $indexContent -Overwrite:$Force.IsPresent
Write-FileIfNeeded -Path (Join-Path $remotionDir "Root.tsx") -Content $rootContent -Overwrite:$Force.IsPresent
Write-FileIfNeeded -Path (Join-Path $remotionDir "MyVideo.tsx") -Content $videoContent -Overwrite:$Force.IsPresent
Write-FileIfNeeded -Path (Join-Path $ProjectDir "tsconfig.json") -Content $tsconfigContent -Overwrite:((-not (Test-Path (Join-Path $ProjectDir "tsconfig.json"))) -or $Force.IsPresent)

$readmeContent = @"
# Remotion Project Helper

This project was prepared with the local Remotion installer.

## Start the helper menu

```bat
start.bat
```

## Common actions

- Start Remotion Studio: choose option `1`
- Open Studio in browser: choose option `2`
- Render MP4: choose option `3`
- Render still image: choose option `4`
- Edit main video file: choose option `6`

## Studio URL

```text
http://localhost:$Port
```

If the page does not load, make sure the Remotion Studio command window is still open.

## Main files

```text
remotion/index.ts
remotion/Root.tsx
remotion/MyVideo.tsx
```

## Output files

```text
out/MyVideo.mp4
out/frame.png
```

## Notes

Remotion can generate a video from code without an existing source video.
You can also place media files in the `public` folder and use them as assets.
"@
Write-FileIfNeeded -Path (Join-Path $ProjectDir "README.md") -Content $readmeContent -Overwrite:((-not (Test-Path (Join-Path $ProjectDir "README.md"))) -or $Force.IsPresent)

Write-Info "Updating package.json scripts."
$packageJsonPath = Join-Path $ProjectDir "package.json"
$package = Read-JsonNoBom -Path $packageJsonPath
if (-not $package.scripts) {
  $package | Add-Member -MemberType NoteProperty -Name scripts -Value ([pscustomobject]@{})
}
$package.scripts | Add-Member -MemberType NoteProperty -Name "remotion:studio" -Value "remotion studio remotion/index.ts --port $Port" -Force
$package.scripts | Add-Member -MemberType NoteProperty -Name "remotion:render" -Value "remotion render remotion/index.ts MyVideo out/MyVideo.mp4" -Force
$package.scripts | Add-Member -MemberType NoteProperty -Name "remotion:still" -Value "remotion still remotion/index.ts MyVideo out/frame.png --frame=30" -Force
$package.scripts | Add-Member -MemberType NoteProperty -Name "remotion:typecheck" -Value "tsc --noEmit" -Force
Write-Utf8NoBom -Path $packageJsonPath -Content ($package | ConvertTo-Json -Depth 20)
Write-Ok "Updated package.json scripts."

$startBatContent = @"
@echo off
setlocal EnableExtensions

set "PROJECT_DIR=$ProjectDir"
set "STUDIO_URL=http://localhost:$Port"
cd /d "%PROJECT_DIR%"

:menu
cls
echo ========================================
echo Remotion Project Helper
echo Project: %PROJECT_DIR%
echo ========================================
echo.
echo 1. Start Remotion Studio in a new window
echo 2. Open Remotion Studio in browser
echo 3. Render MP4 video
echo 4. Render still image
echo 5. Open output folder
echo 6. Edit main video file
echo 7. Install or repair npm dependencies
echo 8. Type-check Remotion files
echo 9. Clean output folder
echo 10. Show Remotion version
echo 0. Exit
echo.
set /p choice=Choose an option: 

if "%choice%"=="1" goto studio
if "%choice%"=="2" goto browser
if "%choice%"=="3" goto render
if "%choice%"=="4" goto still
if "%choice%"=="5" goto outfolder
if "%choice%"=="6" goto editvideo
if "%choice%"=="7" goto install
if "%choice%"=="8" goto typecheck
if "%choice%"=="9" goto clean
if "%choice%"=="10" goto version
if "%choice%"=="0" goto end

echo Invalid option.
pause
goto menu

:studio
echo Starting Remotion Studio in a new command window...
echo Keep the new window open while using Remotion Studio.
start "Remotion Studio" /D "%PROJECT_DIR%" cmd /k "call npm run remotion:studio"
timeout /t 3 /nobreak >nul
start "" "%STUDIO_URL%"
goto menu

:browser
start "" "%STUDIO_URL%"
goto menu

:render
if not exist out mkdir out
echo Rendering MP4 video...
call npm run remotion:render
if errorlevel 1 goto commandfailed
start "" "%PROJECT_DIR%\out"
pause
goto menu

:still
if not exist out mkdir out
echo Rendering still image...
call npm run remotion:still
if errorlevel 1 goto commandfailed
start "" "%PROJECT_DIR%\out"
pause
goto menu

:outfolder
if not exist out mkdir out
start "" "%PROJECT_DIR%\out"
goto menu

:editvideo
where code >nul 2>nul
if not errorlevel 1 (
  code "%PROJECT_DIR%\remotion\MyVideo.tsx"
) else (
  notepad "%PROJECT_DIR%\remotion\MyVideo.tsx"
)
goto menu

:install
echo Installing or repairing npm dependencies...
call npm install
if errorlevel 1 goto commandfailed
pause
goto menu

:typecheck
echo Running TypeScript type-check...
call npm run remotion:typecheck
if errorlevel 1 goto commandfailed
pause
goto menu

:clean
if exist out rmdir /s /q out
mkdir out
echo Output folder cleaned.
pause
goto menu

:version
call npx remotion --version
if errorlevel 1 goto commandfailed
pause
goto menu

:commandfailed
echo.
echo The command failed. Please check the error message above.
pause
goto menu

:end
exit /b 0
"@

Write-FileIfNeeded -Path (Join-Path $ProjectDir "start.bat") -Content $startBatContent -Overwrite:$true

Write-Ok "Remotion setup completed."
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Run: `"$(Join-Path $ProjectDir 'start.bat')`""
Write-Host "  2. Choose option 1 to start Remotion Studio."
Write-Host "  3. Keep the Studio command window open."
Write-Host "  4. Edit: $(Join-Path $remotionDir 'MyVideo.tsx')"
Write-Host "  5. Choose option 3 to render MP4 output."
