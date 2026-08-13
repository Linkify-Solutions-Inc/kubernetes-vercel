import express, { Request, Response } from "express";
import path from "node:path";

const app = express();
const PORT = parseInt(process.env.PORT || "8080", 10);

// Static site — deliberately no scaling (REQ-3.5-1, "web" demo).
app.use(express.static(path.join(__dirname, "..", "public")));

app.get("/healthz", (_req: Request, res: Response) => {
  res.json({ status: "ok" });
});

app.listen(PORT, () => {
  console.log(`web-node listening on :${PORT}`);
});
