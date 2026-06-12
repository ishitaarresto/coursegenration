"""Quick end-to-end test: submit the sample script and poll until done."""
import json
import time
import urllib.request

API = "http://127.0.0.1:8000/api"
content = open("sample_script.txt", encoding="utf-8").read()
body = json.dumps({"content_text": content, "mode": "detailed", "languages": ["en"]}).encode()
req = urllib.request.Request(API + "/courses/generate", data=body,
                             headers={"Content-Type": "application/json"}, method="POST")
job = json.loads(urllib.request.urlopen(req).read())
job_id = job["id"]
print(f"Job {job_id} submitted. Polling...")

while True:
    time.sleep(3)
    j = json.loads(urllib.request.urlopen(f"{API}/jobs/{job_id}").read())
    pct = j["progress"]
    step = j["step"]
    print(f"  {pct}% — {step}")
    if j["status"] == "completed":
        course_id = j["course_id"]
        print(f"\nDONE! course_id = {course_id}")
        course = json.loads(urllib.request.urlopen(f"{API}/courses/{course_id}").read())
        print(f"\nCourse: {course['title']}")
        print(f"Description: {course['description'][:120]}...")
        print(f"Objectives: {len(course['learning_objectives'])}")
        print(f"Modules: {len(course['modules'])}")
        for m in course["modules"]:
            print(f"  Module: {m['title']} ({len(m['lessons'])} lessons)")
            for l in m["lessons"]:
                lid = l["id"]
                print(f"    Lesson [{lid}]: {l['title']}")
                print(f"      Takeaways : {len(l['key_takeaways'])}")
                print(f"      Examples  : {len(l['real_world_examples'])}")
                print(f"      Safety    : {len(l['safety_scenarios'])}")
                print(f"      Slides URL: {API}/courses/{course_id}/lessons/{lid}/slides")
        break
    if j["status"] == "failed":
        print(f"FAILED: {j['error']}")
        break
