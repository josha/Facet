import subprocess, sys, shutil, os, json
ROOT="/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/LuauUI"
SCRATCH="/private/tmp/claude-501/-Users-josha-Library-CloudStorage-Dropbox-Documents-UntitledRacingGame/a0b839a2-f4bc-48a8-a6b3-940474a9b7b4/scratchpad"
os.chdir(ROOT)

MUTATIONS = [
 ("M1 compact rung removed", "src/layout/solver.luau",
  "child.compactText ~= nil and (rung >= FLOOR_COMPACT or ctx.compact[child.id] == true)",
  "child.compactText ~= nil and (ctx.compact[child.id] == true)", ["text_degrade_cascade"]),
 ("M7 availW clamp reverted to the parent's offer", "src/layout/solver.luau",
  "if singleLine and availW ~= math.huge then\n\t\t\trecordTextFacts(ctx, node, m, m.width > availW, font, size, naturalW, false)\n\t\t\treturn math.min(m.width, availW) + pl + pr, m.height + pt + pb",
  "if singleLine and innerMaxW ~= math.huge then\n\t\t\trecordTextFacts(ctx, node, m, m.width > innerMaxW, font, size, naturalW, false)\n\t\t\treturn math.min(m.width, innerMaxW) + pl + pr, m.height + pt + pb",
  ["text_degrade_cascade", "large_text_matrix"]),
 ("M8 rungs stack instead of re-running from the basis", "src/layout/solver.luau",
  "table.clear(shrunk)\n\t\t\tabsorbed = runTiers()",
  "absorbed += runTiers()", ["text_degrade_cascade", "stack_distribution"]),
]

results=[]
for name, path, old, new, specs in MUTATIONS:
    src=open(path).read()
    if src.count(old) != 1:
        results.append((name, "SETUP-FAIL", f"anchor found {src.count(old)}x in {path}", []))
        continue
    backup=SCRATCH+"/backup_"+os.path.basename(path)
    shutil.copyfile(path, backup)
    open(path,"w").write(src.replace(old,new))
    reddened=[]
    try:
        for spec in specs:
            p=subprocess.run(["lune","run","tests/run_one",spec],capture_output=True,text=True,timeout=900)
            out=p.stdout+p.stderr
            import re
            out=re.sub(r"\x1b\[[0-9;]*m","",out)
            for line in out.split("\n"):
                if line.strip().startswith("✗"):
                    reddened.append(spec+" :: "+line.strip()[1:].strip())
    finally:
        shutil.copyfile(backup, path)
    results.append((name, "BIT" if reddened else "NO-BITE", path, reddened))

for name,status,path,red in results:
    print(f"\n### {name}  -> {status}")
    if status=="SETUP-FAIL": print("   ", path); continue
    for r in red[:6]:
        print("    RED:", r)
    if len(red)>6: print(f"    ... and {len(red)-6} more")
