# Fully ephemeral DispVM's

The steps below outline how to make all PVH DispVM's permanently fully ephemeral.
All data written to the disk will be encrypted with an ephemeral encryption key
only stored in RAM. The encryption and encryption key generation is handled by dom0 and is
thus inaccessible to the vm. Currently Qubes implements this (when ephemeral=True and vm:root rw 0) 
only for data written to xvda and swap but not for data written to xvdb (i.e /rw). This patch 
fixes the issue and encrypts ephemerally all data written to disk from a PVH DispVM.

This is accomplished by making xvda, xvdb read-only and ephemeral=True the defaults for DispVM's (three line 
patching of dispvm.py) and by patching /init of initramfs of the pvh kernel so that all data writes are routed 
to xvdc using dmapper. This routing is already partially accomplished in qubes by mapping all writes
to xvda to dmroot when vm:root rw is set to False. The patch now routes in addition all writes to xvdb 
to dmhome and seamlessly relabels in fstab xvdb to dmhome, before /sbin/init is initialized.
The fact that xvda and xvdb are set to be readonly and only xvdc is writeable and ephemerally encrypted 
ensures that no data escape is possible. 

### Step 1. 

First identify all the names of all the linux kernels that are in use,
for instance by looking at the directory names in 

>   /var/lib/qubes/vm-kernels

For example on R4.1 you might see a directory named 5.10.90-1.fc32 in
/var/lib/qubes/vm-kernels. You can also directly find which kernel a vm uses
by typing 
```
  qvm-prefs [vmname] kernel
```

### Step 2. 

Once you have identified the kernel to patch, say 5.10.90-1.fc32, issue
```
  sudo sh ./patch_initramfs.py 5.10.90-1.fc32
```
This will patch the /init file in the initramfs of the kernel 5.10.90-1.fc32.

### Step 3. 

Now you need to patch the DispVM code of Qubesd so that all DispVM
are by default generated with the xvda and xvdb set to read-only and xvdc
set as ephemeral. This amounts to patching the file

>   /usr/lib/python3.8/site-packages/qubes/vm/dispvm.py

by appending on line 138,

>         self.volume_config['root']['rw'] = False
>         self.volume_config['private']['rw'] = False
>         self.volume_config['volatile']['ephemeral'] = True

Alternatively you can copy the dispvm.py included here. 

### Step 4

Find the list of all HVM DispVM's in the system (usually just sys-usb and sys-net).
For each such VM, say in this case sys-net, issue
```
qvm-volume config sys-net:private rw 1
```
The command above disables the patch for these HVM's. I plan on fixing this issue in the
next iteration of the patch. Reboot the system and you are done.

## Additional comments*

### Note 1. 
An alernative to patching the code of dispvm is as follows: Given an
AppVM you can issue

```
  qvm-volume config appvm:root rw 0
  qvm-volume config appvm:private rw 0
  qvm-volume config appvm:volatile ephemeral 1
```

Then all the DispVM's arising from "qvm-run --dispvm appvm"
will be fully ephemeral.

This however is not the recommended use; there are many caveats.
For instance these settings might not be persistent across reboots
and for example the current named DispVM's are not affected by
these changes to the AppVM setting. Unless you have studied the
code of qubesd you might experience many counterintuitive "features".

### Note 2.
You can check that the initramfs patch is in effect inside
a DispVM by typing "df -h" and checking that you see "dmhome" instead
of "xvdb"

### Note 3.
At present you cannot make HVM based DispVM's fully persistent.
The only HVM based DispVM's on your system are usually sys-usb and sys-net.
In the unlikely event that they refuse to boot after these changes issue
the command

```  
  qvm-volume config sys-usb:root rw 1
  qvm-volume config sys-usb:private rw 1
```
which should fix the issue, as it effectively disables the patch in initramfs.



