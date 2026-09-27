# Historical contribution ideas

Preserved from the earlier contributor guide. These are planning notes, not verified bugs or beginner tasks; some listed work is already implemented (including webhook alerts). Check current source and open issues before proposing work.



Earlier roadmap table (difficulty labels are historical):

| Idea | Difficulty | Notes |
|---|---|---|
| Alert threshold notifications | Medium | Trigger webhook when CPU/RAM exceeds a threshold |
| GPU temperature metric | Easy | `psutil` has limited GPU support; may need `pynvml` for NVIDIA |
| Per-process CPU/memory breakdown | Medium | Already available in psutil, needs schema changes |
| Authentication on the dashboard UI | Medium | Currently only protects the delete/clean endpoints |
| Prometheus `/metrics` endpoint | Medium | Add an exporter alongside `/data` |
| Time-zone aware timestamps | Easy | Store UTC, convert in dashboard |
| Dark mode toggle | Easy | CSS variable swap in `dashboard.html` — **implemented** |
| Docker container monitoring | Easy | Subprocess-based collection via `docker ps --all`; graceful no-op when Docker is absent — **implemented** |
| PostgreSQL backend | Hard | Abstraction layer in `server.py`, Docker Compose update |
| Alertmanager integration | Hard | Pub/sub or webhook from the server on threshold breach |

---

