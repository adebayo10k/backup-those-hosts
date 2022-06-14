# backup-those-hosts


## Project Background
My synchronisation, encryption and backup routine. 



## Typical use for host-config-backup.sh

Backup host configuration files to single location from which they can be synchronised and then archived safely to ensure Availability. 

## Installation

This repository maintains relative symbolic links to required files located in other repositories. 
If you want those target files to be recreated on your system at clone-time (rather that just dangling symlinks), the value of the `core.symlinks` attribute in your local git must be configured to `true`.

``` bash
git config --list
git config --global core.symlinks true
git config core.symlinks	#true
git config --list
```

---



