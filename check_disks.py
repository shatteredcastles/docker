import psutil
print("Mounts detected by psutil:")
for p in psutil.disk_partitions(all=True):
    print(f"Device: {p.device}, Mount: {p.mountpoint}, Fstype: {p.fstype}")
