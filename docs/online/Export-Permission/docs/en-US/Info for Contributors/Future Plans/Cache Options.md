# Cache Options

## PLANS

### Cache on Disk

Export-Permission > EFPosh > Entity Framework Core > Database Provider

[DotNet Core CLI](https://learn.microsoft.com/en-us/ef/core/providers/?tabs=dotnet-core-cli)

[EFPosh](https://github.com/Ryan2065/EFPosh)

#### First Level Cache

In-Memory, maintained by the EF DbContext

#### Second Level Cache

External Cache, distributed

Export-Permission > EFPosh > Entity Framework Core > EntityFrameworkCore.Cacheable > Memcached

[EntityFrameworkCore.Cacheable](https://github.com/SteffenMangold/EntityFrameworkCore.Cacheable)

### $PSCache: PowerShell-Only In-Process Caches

Used for things that can't be stored on disk like PSSessions and CIM Sessions.
