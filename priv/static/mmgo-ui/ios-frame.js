// Frame — minimal sized container that auto-scales to fit the viewport.
// Keeps the IOSDevice export name so call sites don't change.

function IOSDevice({ children, width = 402, height = 874, dark = false }) {
  const [scale, setScale] = React.useState(1);

  React.useEffect(()=>{
    function fit(){
      // leave a little margin and room for the side Tweaks panel
      const margin = 40;
      const sideW = 280; // tweaks panel + gap, when shown
      const availW = window.innerWidth - margin - sideW;
      const availH = window.innerHeight - margin;
      const s = Math.min(1, availW / width, availH / height);
      setScale(s);
    }
    fit();
    window.addEventListener('resize', fit);
    return ()=> window.removeEventListener('resize', fit);
  }, [width, height]);

  return (
    <div style={{
      width: width * scale, height: height * scale,
      flexShrink: 0,
    }}>
      <div style={{
        width, height,
        transform: `scale(${scale})`,
        transformOrigin: 'top left',
        borderRadius: 18,
        overflow: 'hidden',
        position: 'relative',
        background: dark ? 'oklch(0.16 0.03 258)' : 'oklch(0.94 0.022 82)',
        boxShadow:
          '0 30px 60px rgba(0,0,0,0.45), 0 8px 16px rgba(0,0,0,0.25)',
        isolation: 'isolate',
      }}>
        {children}
      </div>
    </div>
  );
}

Object.assign(window, { IOSDevice });
