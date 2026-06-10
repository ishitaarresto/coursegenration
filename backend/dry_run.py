"""Dry run — generate a course and print full system status."""
import json
import time
import urllib.request

BASE = "http://127.0.0.1:8000/api"

CONTENT = """
Fire Safety in the Workplace

Fire requires three elements: heat, fuel, and oxygen (the fire triangle).
Removing any one element extinguishes the fire.

Common workplace fire hazards:
- Overloaded electrical sockets
- Flammable liquids stored incorrectly
- Blocked fire exits
- Faulty equipment left running

Fire extinguisher types:
- Red (Water): wood, paper, fabric - NOT electrical
- Black (CO2): electrical equipment, flammable liquids
- Cream (Foam): flammable liquids
- Blue (Dry Powder): most fires but leaves residue

Emergency procedure:
1. Raise the alarm immediately
2. Call emergency services (999/112)
3. Evacuate using nearest safe exit
4. Do NOT use lifts
5. Assemble at designated muster point
6. Do NOT re-enter building

Fire wardens must conduct roll call at muster point.
Never tackle a fire if it is larger than a waste bin.
"""

print("=" * 55)
print("  DRY RUN — AI Safety LMS")
print("=" * 55)

# Step 1: Submit
print("\n[1] Submitting content to Claude AI...")
body = json.dumps({"content_text": CONTENT, "mode": "detailed", "languages": ["en"]}).encode()
req = urllib.request.Request(f"{BASE}/courses/generate", data=body,
    headers={"Content-Type": "application/json"}, method="POST")
job = json.loads(urllib.request.urlopen(req).read())
job_id = job["id"]
print(f"    Job ID: {job_id} — queued")

# Step 2: Poll
print("\n[2] Generating course (Claude AI working)...")
while True:
    time.sleep(3)
    j = json.loads(urllib.request.urlopen(f"{BASE}/jobs/{job_id}").read())
    bar = "#" * (j["progress"] // 5) + "-" * (20 - j["progress"] // 5)
    print(f"    [{bar}] {j['progress']}%  {j['step']}")
    if j["status"] == "completed":
        course_id = j["course_id"]
        break
    if j["status"] == "failed":
        print(f"    FAILED: {j['error']}")
        exit(1)

# Step 3: Print results
print(f"\n[3] Course generated! ID = {course_id}")
c = json.loads(urllib.request.urlopen(f"{BASE}/courses/{course_id}").read())
print(f"\n    Title       : {c['title']}")
print(f"    Description : {c['description'][:80]}...")
print(f"    Objectives  : {len(c['learning_objectives'])}")
print(f"    Modules     : {len(c['modules'])}")
total_lessons = sum(len(m["lessons"]) for m in c["modules"])
total_slides  = sum(len(l["slides"]) for m in c["modules"] for l in m["lessons"])
print(f"    Lessons     : {total_lessons}")
print(f"    Slides      : {total_slides} total")

print(f"\n[4] Lesson breakdown:")
for m in c["modules"]:
    print(f"\n    MODULE: {m['title']}")
    for l in m["lessons"]:
        print(f"      └ Lesson [{l['id']}]: {l['title']}")
        print(f"          Takeaways : {len(l['key_takeaways'])}")
        print(f"          Examples  : {len(l['real_world_examples'])}")
        print(f"          Safety    : {len(l['safety_scenarios'])}")
        print(f"          Slides URL: http://127.0.0.1:8000/api/courses/{course_id}/lessons/{l['id']}/slides")

print("\n[5] System check:")
print(f"    App URL     : http://127.0.0.1:8000")
print(f"    API docs    : http://127.0.0.1:8000/docs")
print(f"    Course JSON : http://127.0.0.1:8000/api/courses/{course_id}")
print("\n    ALL SYSTEMS OK")
print("=" * 55)
