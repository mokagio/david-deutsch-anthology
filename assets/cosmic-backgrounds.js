(() => {
  const canvas = document.querySelector('#cosmic-background');
  const context = canvas.getContext('2d');
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const palette = ['152,173,231', '183,163,221', '205,156,213', '173,170,210'];
  const pointer = { x: 0.5, y: 0.5, tx: 0.5, ty: 0.5 };
  const scroll = { y: scrollY, ty: scrollY };
  let width;
  let height;
  let scale;
  let stars = [];

  const randomStar = () => ({
    x: Math.random(),
    y: Math.random(),
    z: 0.15 + Math.random() * 0.85,
    phase: Math.random() * Math.PI * 2,
    color: palette[Math.floor(Math.random() * palette.length)]
  });

  function resize() {
    scale = Math.min(devicePixelRatio || 1, 2);
    width = innerWidth;
    height = innerHeight;
    canvas.width = width * scale;
    canvas.height = height * scale;
    context.setTransform(scale, 0, 0, scale, 0, 0);
    stars = Array.from({ length: Math.min(180, Math.floor(width * height / 7500)) }, randomStar);
  }

  function draw(time) {
    context.clearRect(0, 0, width, height);
    stars.forEach((star) => {
      const layer = star.z ** 2;
      const twinkle = reduceMotion ? 0 : Math.sin(time / 2400 + star.phase) * 0.07;
      const x = star.x * width + (pointer.x - 0.5) * 105 * layer;
      const rawY = star.y * height + (pointer.y - 0.5) * 68 * layer - scroll.y * 0.075 * layer;
      const y = ((rawY % height) + height) % height;

      context.fillStyle = `rgba(${star.color},${0.14 + star.z * 0.4 + twinkle})`;
      context.beginPath();
      context.arc(x, y, star.z * (1.25 + 0.7 * layer), 0, Math.PI * 2);
      context.fill();
    });
  }

  function frame(time) {
    pointer.x += (pointer.tx - pointer.x) * 0.045;
    pointer.y += (pointer.ty - pointer.y) * 0.045;
    scroll.y += (scroll.ty - scroll.y) * 0.08;
    draw(time);
    requestAnimationFrame(frame);
  }

  addEventListener('resize', resize);
  addEventListener('pointermove', (event) => {
    pointer.tx = event.clientX / width;
    pointer.ty = event.clientY / height;
  });
  addEventListener('scroll', () => { scroll.ty = scrollY; }, { passive: true });
  resize();
  requestAnimationFrame(frame);
})();
