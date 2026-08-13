import express, { Request, Response } from "express";

const app = express();
const PORT = parseInt(process.env.PORT || "3000", 10);

app.get("/", (_req: Request, res: Response) => {
  res.json({ app: "api-node", message: "Mini-PaaS demo API" });
});

// Liveness/readiness probe target.
app.get("/healthz", (_req: Request, res: Response) => {
  res.json({ status: "ok" });
});

// CPU burn for the autoscaling demo. `ms` controls how long each request
// pegs a CPU core. Deliberately a busy loop so the CPU metric is real.
app.get("/work", (req: Request, res: Response) => {
  const ms = Math.min(parseInt(String(req.query.ms || "2000"), 10) || 2000, 10000);
  const end = Date.now() + ms;
  while (Date.now() < end) {
    // busy loop — burns CPU on purpose
  }
  res.json({ app: "api-node", burned: ms, pid: process.pid });
});

app.listen(PORT, () => {
  console.log(`api-node listening on :${PORT}`);
});
