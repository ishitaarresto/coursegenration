"""Test video render pipeline."""
import json
import time
import urllib.request

BASE = "http://127.0.0.1:8000/api"
COURSE_ID = 1
LESSON_ID = 1
LANG = "en"

req = urllib.request.Request(
    f"{BASE}/courses/{COURSE_ID}/lessons/{LESSON_ID}/render?lang={LANG}",
    method="POST",
)
res = json.loads(urllib.request.urlopen(req).read())
print("Render started:", res)
rid = res["render_id"]

print("Polling status...")
for _ in range(60):
    time.sleep(5)
    s = json.loads(urllib.request.urlopen(f"{BASE}/renders/{rid}/status").read())
    status = s["status"]
    print(f"  {status}")
    if status == "completed":
        url = f"http://127.0.0.1:8000{BASE}/courses/{COURSE_ID}/lessons/{LESSON_ID}/video?lang={LANG}"
        print(f"\nVIDEO READY: {BASE}/courses/{COURSE_ID}/lessons/{LESSON_ID}/video?lang={LANG}")
        break
    if status == "failed":
        print("FAILED:", s["error"])
        break
