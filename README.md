# Fully ephemeral DispVM's

The steps below outline how to make all PVH DispVM's permanently fully ephemeral.
All data written to the disk will be encrypted with an ephemeral encryption key
only stored in RAM. Currently Qubes implements this (when ephemeral=True) only
for data written to xvda but not for data written to xvdb (i.e /rw) or data
written to swap. This patch fixes the issue and encrypts ephemerally all data 
written to disk from a PVH DispVM.

### Step 1. 

First identify all the names of all the linux kernels that are in use,
for instance by looking at the directory names in 

> /var/lib/qubes/vm-kernels

For example on R4.1 you might see a directory named 5.10.90-1.fc32 in
/var/lib/qubes/vm-kernels. You can also directly find which kernel a vm uses
by typing 

> qvm-prefs [vmname] kernel

### Step 2. 

Once you have identified the kernel to patch, say 5.10.90-1.fc32, issue

> sudo sh ./patch_initramfs.py 5.10.90-1.fc32

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

Alternatively you can copy the dispvm.py included here. Reboot the system
and you are done.

## Additional comments*

### Note 1. 
An alernative to patching the code of dispvm is as follows: Given an
AppVM you can issue


>   qvm-volume config appvm:root rw 0
>   qvm-volume config appvm:private rw 0
>   qvm-volume config appvm:volatile ephemeral 1


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

>    qvm-volume config sys-usb:root rw 1
>    qvm-volume config sys-usb:private rw 1

which should fix the issue, as it effectively disables the patch in initramfs.



