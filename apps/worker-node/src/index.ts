import express, { Request, Response } from "express";

const app = express();
const PORT = parseInt(process.env.PORT || "8081", 10);

// Background "queue" work: burn CPU for WORK_PER_TICK_MS milliseconds each second.
// Raise WORK_PER_TICK_MS in the Deployment to drive the worker's HPA, or lower it
// to quiet it down. Default 200ms/sec ≈ 20% of one core — below the 50% HPA target.
const workPerTickMs = Math.min(
  parseInt(process.env.WORK_PER_TICK_MS || "200", 10) || 200,
  900
);

setInterval(() => {
  const end = Date.now() + workPerTickMs;
  while (Date.now() < end) {
    // busy loop — simulates processing a batch of jobs
  }
}, 1000);

app.get("/", (_req: Request, res: Response) => {
  res.json({ app: "worker-node", mode: "background", workPerTickMs });
});

app.get("/healthz", (_req: Request, res: Response) => {
  res.json({ status: "ok" });
});

app.listen(PORT, () => {
  console.log(`worker-node listening on :${PORT} (${workPerTickMs}ms work/sec)`);
});
