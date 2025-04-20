# lsoldrpm

list old RPMs found in a directory

An RPM in a directory is considered old if there is a RPM for the
same module with a newer version in that same directory.  For example,
if we have these RPM files:

    gcc-3.4.4-2.i386.rpm
    gcc-3.4.5-2.i386.rpm

then gcc-3.4.4-2.i386.rpm is an old RPM.  However if we have these RPMs:

    audit-1.0.12-1.EL4.i386.rpm
    audit-libs-1.0.12-1.EL4.i386.rpm

then neither is an old RPM because they refer to two different modules.

There is a special exception.  Multiple kernel RPMs may (and often are)
installed on the same system.  Thus for these RPMs:

    kernel-2.6.9-22.0.2.EL.i686.rpm
    kernel-2.6.9-34.EL.i686.rpm
    kernel-devel-2.6.9-22.0.2.EL.i686.rpm
    kernel-devel-2.6.9-34.EL.i686.rpm
    kernel-doc-2.6.9-22.0.2.EL.noarch.rpm
    kernel-doc-2.6.9-34.EL.noarch.rpm

none of them are considered old unless the -k flag is given.  With the
exception of the kernel-utils RPM, all kernel-*.rpm files fit into
this special case.


# To install

```sh
sudo make install
```


# Example

```sh
$ /usr/local/bin/lsoldrpm /var/tmp/rpm-set-dir
```


# To use

```
/usr/local/bin/lsoldrpm [-h] [-v lvl] [-V] [-b|-e|-m] [-k] [-n] [-r] dir

    -h	    print help and exit
    -v lvl  verbose / debug level
    -V	    print version and exit

    -b      print basename of RPM file (def: print pathname)
    -e      print extended module-version-releases (def: print pathname)
    -m      print module names (def: print pathname)

    -k      list older kernel based RPM (def: don't)
    -n      print newest RPMs (def: list just older RPMs)
    -r      recursively search under dir (def: ignore subdirectories)

    dir     directory into which RPM files may be found

    NOTE: Ignores non-files and filenames without the .rpm suffix

lsoldrpm version: 1.5.1 2025-03-27
```


# Reporting Security Issues

To report a security issue, please visit "[Reporting Security Issues](https://github.com/lcn2/lsoldrpm/security/policy)".
