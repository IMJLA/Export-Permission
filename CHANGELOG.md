# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [0.0.419] - 2024-12-01
### Fixed
- bugfix permission module for thishostname caching

## [0.0.418] - 2024-12-01
### Fixed
- bugfixes in new version of permission module for retrieving threadcount from cache

## [0.0.417] - 2024-11-30
### Added
- implement cache for clearer code and logs

## [0.0.416] - 2024-11-24
### Changed
- move repetitive params to cache, and make dictionary keys more robust by forcing string keys

## [0.0.415] - 2024-11-24
### Changed
- expand use of accountproperty

## [0.0.414] - 2024-11-23
### Changed
- improve log file

## [0.0.413] - 2024-11-23
### Changed
- improve log file

## [0.0.412] - 2024-11-23
### Added
- implement AccountProperty param

## [0.0.411] - 2024-11-23
### Added
- implement simplified get-currentdomain for bugfix

## [0.0.410] - 2024-11-23
### Added
- add AccountProperty param as far as Get-PermissionPrincipal in prep for implementation in report

## [0.0.409] - 2024-11-19
### Changed
- expand cache usage

## [0.0.408] - 2024-11-17
### Changed
- cleanup

## [0.0.407] - 2024-11-16
### Changed
- cleanup

## [0.0.406] - 2024-11-10
### Fixed
- fix output type

## [0.0.405] - 2024-11-10
### Added
- implement unified in-process cache

## [0.0.404] - 2024-11-03
### Fixed
- bugfix must now pass directoryentrycache as ref var now that dependencies have been updated

## [0.0.403] - 2024-11-03
### Added
- implement new-permissioncache

## [0.0.402] - 2024-10-18
### Changed
- update adsi module

## [0.0.401] - 2024-10-13
### Fixed
- bugfix log output

## [0.0.400] - 2024-10-12
### Added
- add inline comments in psakefile

## [0.0.399] - 2024-10-12
### Changed
- eliminate unnecessary external file

## [0.0.398] - 2024-10-12
### Fixed
- bugfix get-relativeuri

## [0.0.397] - 2024-10-12
### Changed
- psakefile use paths instead of uris

## [0.0.396] - 2024-10-12
### Fixed
- bugfix psakefile

## [0.0.395] - 2024-10-12
### Changed
- update psakefile output to use relative paths

## [0.0.394] - 2024-10-12
### Changed
- troubleshoot psakefile

## [0.0.393] - 2024-10-12
### Changed
- troubleshoot psakefile

## [0.0.392] - 2024-10-12
### Fixed
- bugfix was not searching servicebyname cache

## [0.0.391] - 2024-10-06
### Removed
- remove build debug pause

## [0.0.390] - 2024-10-06
### Changed
- update test result output file

## [0.0.389] - 2024-10-06
### Changed
- debug build

## [0.0.388] - 2024-10-06
### Changed
- troubleshoot pester config

## [0.0.387] - 2024-10-06
### Changed
- results in desired location

## [0.0.386] - 2024-10-06
### Changed
- default results location

## [0.0.385] - 2024-10-06
### Changed
- test results still outputting to wrong place

## [0.0.384] - 2024-10-06
### Fixed
- bugfix incorrect variable type

## [0.0.383] - 2024-10-06
### Changed
- try redirecting tests output file up one folder

## [0.0.382] - 2024-10-06
### Changed
- try redirecting tests output file

## [0.0.381] - 2024-10-06
### Changed
- try redirecting tests output file

## [0.0.380] - 2024-10-06
### Changed
- reduce pester verbosity

## [0.0.379] - 2024-10-06
### Fixed
- fix testsdir

## [0.0.378] - 2024-10-06
### Changed
- update debug output in psakefile

## [0.0.377] - 2024-10-06
### Changed
- lets see where test results appear

## [0.0.376] - 2024-10-06
### Changed
- troubleshoot psake test output location

## [0.0.375] - 2024-10-03
### Changed
- update psntfs module

## [0.0.374] - 2024-10-03
### Removed
- delete extra blank lines

## [0.0.373] - 2024-10-03
### Changed
- improved error handling

## [0.0.372] - 2024-10-02
### Removed
- remove debug breakpoints

## [0.0.371] - 2024-10-02
### Changed
- rename psake task to be more descriptive

## [0.0.370] - 2024-10-02
### Changed
- updates to adsi module to handle windows built-in sids

## [0.0.369] - 2024-09-26
### Changed
- update adsi module to properly handle capability sids
- updated adsi module to properly handle app authority capability SIDs

## [0.0.367] - 2024-09-15
### Changed
- update dev tests, integrate bugfixes from dependencies

## [0.0.366] - 2024-09-15
### Fixed
- bugfix get-directoryentry caching

## [0.0.365] - 2024-09-14
### Fixed
- bugfixes and additional debug tests

## [0.0.364] - 2024-09-04
### Changed
- update adsi module

## [0.0.363] - 2024-09-03
### Changed
- single-threaded by default at least until multithreading is more rigorously tested

## [0.0.362] - 2024-09-03
### Changed
- update psrunspace module

## [0.0.361] - 2024-09-03
### Changed
- update psrunspace module

## [0.0.360] - 2024-09-03
### Changed
- update psrunspace module

## [0.0.359] - 2024-09-03
### Changed
- update psrunspace module

## [0.0.358] - 2024-09-03
### Changed
- update psrunspace module

## [0.0.357] - 2024-06-16
### Added
- add host output for publication step

## [0.0.356] - 2024-06-16
### Fixed
- fix build bugs

## [0.0.355] - 2024-06-16
### Changed
- test run

## [0.0.354] - 2024-06-16
### Added
- implement write-host in build scripts

## [0.0.353] - 2024-06-16
### Changed
- test run

## [0.0.352] - 2024-06-16
### Fixed
- fix remove broken precondition on createmarkdownhelpfolder psake task

## [0.0.351] - 2024-06-16
### Removed
- remove unnecessary host output in the buildportablerelease psake task

## [0.0.350] - 2024-06-16
### Added
- add new-portablescript

## [0.0.349] - 2024-06-16
### Changed
- all in on write-host

## [0.0.348] - 2024-06-16
### Changed
- move write-host functionality into find-newversion

## [0.0.347] - 2024-06-16
### Changed
- cleanup newversion console output

## [0.0.346] - 2024-06-16
### Fixed
- fix newversion display bug during build

## [0.0.345] - 2024-06-16
### Changed
- test

## [0.0.344] - 2024-06-16
### Changed
- reduce verbosity of find-newversion to host

## [0.0.343] - 2024-06-16
### Changed
- test

## [0.0.342] - 2024-06-16
### Changed
- improved Find-NewVersion

## [0.0.341] - 2024-06-16
### Fixed
- fix extra newline in convertfrom-svg output

## [0.0.340] - 2024-06-16
### Fixed
- fix outdated metadata in portable script version

## [0.0.339] - 2024-06-16
### Changed
- minor dependency updates

## [0.0.338] - 2024-06-16
### Changed
- test build

## [0.0.337] - 2024-06-16
### Added
- implement changelogmanagement module

## [0.0.335] - 2024-06-16
### Changed
- improve console output

## [0.0.334] - 2024-06-16
### Changed
- cleanup console output

## [0.0.333] - 2024-06-16
### Changed
- split up psake build tasks

## [0.0.332] - 2024-06-16
### Changed
- split up psake build tasks

## [0.0.331] - 2024-06-16
### Fixed
- art tasks

## [0.0.330] - 2024-06-16
### Changed
- remove debug comments

## [0.0.329] - 2024-06-16
### Changed
- uncomment from debugging

## [0.0.328] - 2024-06-16
### Fixed
- get-exportsize

## [0.0.327] - 2024-06-16
### Changed
- test

## [0.0.326] - 2024-06-16
### Changed
- use io.path combine method

## [0.0.325] - 2024-06-16
### Changed
- troubleshoot get-exportsize

## [0.0.324] - 2024-06-16
### Changed
- troubleshoot convertfrom-svg

## [0.0.323] - 2024-06-16
### Changed
- troubleshoot convertfrom-svg

## [0.0.322] - 2024-06-16
### Changed
- troubleshoot convertfrom-svg

## [0.0.321] - 2024-06-16
### Changed
- troubleshoot convertfrom-svg

## [0.0.320] - 2024-06-16
### Changed
- troubleshoot convertfrom-svg

## [0.0.319] - 2024-06-16
### Changed
- test

## [0.0.318] - 2024-06-16
### Changed
- troubleshoot convertfrom-svg

## [0.0.317] - 2024-06-16
### Changed
- add debugging for convertfrom-svg

## [0.0.316] - 2024-06-16
### Changed
- add debugging for get-exportsize

## [0.0.315] - 2024-06-16
### Changed
- add debugging for get-exportsize

## [0.0.314] - 2024-06-16
### Changed
- add console output to debug convertfrom-svg

## [0.0.313] - 2024-06-16
### Changed
- cleanup console output

## [0.0.312] - 2024-06-16
### Changed
- cleanup inkscape debug output

## [0.0.311] - 2024-06-16
### Fixed
- Get-ExportSize and cleanup source control console output

## [0.0.310] - 2024-06-16
### Changed
- test with favicon width of 512

## [0.0.309] - 2024-06-16
### Changed
- troubleshoot Export-Inkscape

## [0.0.308] - 2024-06-16
### Changed
- troubleshoot inkscape

## [0.0.307] - 2024-06-16
### Changed
- troubleshoot inkscape

## [0.0.306] - 2024-06-16
### Changed
- add invoke-inkscape build output to console for debugging

## [0.0.305] - 2024-06-16
### Fixed
- export-inkscape

## [0.0.304] - 2024-06-16
### Changed
- troubleshoot inkscape

## [0.0.303] - 2024-06-16
### Changed
- troubleshoot inkscape

## [0.0.302] - 2024-06-16
### Changed
- reduce verbosity of psakefile output regarding pester now that troubleshooting and changes are complete

## [0.0.301] - 2024-06-16
### Fixed
- SourceCode tests

## [0.0.300] - 2024-06-16
### Fixed
- Pester invocatin

## [0.0.299] - 2024-06-16
### Changed
- troubleshoot pester

## [0.0.298] - 2024-06-16
### Changed
- troubleshoot Pester

## [0.0.297] - 2024-06-16
### Fixed
- NoPublish feature

## [0.0.296] - 2024-06-16
### Fixed
- NoPublish feature

## [0.0.295] - 2024-06-16
### Fixed
- NoPublish feature

## [0.0.294] - 2024-06-16
### Fixed
- NoPublish feature

## [0.0.293] - 2024-06-16
### Fixed
- pester configuration

## [0.0.292] - 2024-06-16
### Fixed
- pester configuration

## [0.0.291] - 2024-06-16
### Fixed
- pester configuration

## [0.0.290] - 2024-06-16
### Fixed
- pester configuration

## [0.0.289] - 2024-06-16
### Fixed
- pester configuration

## [0.0.288] - 2024-06-16
### Fixed
- pester run path

## [0.0.287] - 2024-06-16
### Fixed
- pester run path

## [0.0.286] - 2024-06-16
### Fixed
- pester run path

## [0.0.285] - 2024-06-16
### Fixed
- pester param hashtable string

## [0.0.284] - 2024-06-16
### Fixed
- pester param hashtable string

## [0.0.283] - 2024-06-16
### Fixed
- psake output formatting

## [0.0.282] - 2024-06-16
### Fixed
- psake output formatting

## [0.0.281] - 2024-06-16
### Changed
- add out folder to gitignore

## [0.0.280] - 2024-06-16
### Changed
- keep the out directory

## [0.0.279] - 2024-06-16
### Changed
- clear test results from out directory

## [0.0.278] - 2024-06-16
### Fixed
- git add command due to new psakefile location

## [0.0.277] - 2024-06-16
### Fixed
- psakefile after build changes

## [0.0.276] - 2024-06-16
### Fixed
- psakefile after build changes

## [0.0.275] - 2024-06-16
### Fixed
- psakefile after build changes

## [0.0.274] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.3] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.2] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.1] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.272] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.271] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.270] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.269] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.268] - 2024-06-16
### Changed
- implementing pssvg and docusaurus and inkscape

## [0.0.267] - 2024-06-16
### Changed
- implementing docusaurus and pssvg and inkscape

## [0.0.266] - 2024-06-16
### Changed
- implementing docusaurus and pssvg and inkscape

## [0.0.265] - 2024-05-28
### Changed
- restored prtg functionality

## [0.0.264] - 2024-05-22
### Fixed
- export-logcsv -progressparentid

## [0.0.263] - 2024-05-22
### Changed
- implement out-permission to output objects

## [0.0.262] - 2024-04-07
### Changed
- new psdfs version

## [0.0.261] - 2024-04-07
### Changed
- remove blank lines from portable version

## [0.0.260] - 2024-04-07
### Fixed
- portable script version param block

## [0.0.259] - 2024-04-07
### Fixed
- portable script version param block

## [0.0.258] - 2024-04-07
### Changed
- replace new-psscriptfileinfo with new-scriptfileinfo to troubleshoot build errors

## [0.0.257] - 2024-04-07
### Changed
- test new-psscriptfileinfo

## [0.0.256] - 2024-04-07
### Fixed
- portable script construction

## [0.0.255] - 2024-04-07
### Fixed
- portable script construction

## [0.0.254] - 2024-04-07
### Fixed
- portable script construction

## [0.0.253] - 2024-04-07
### Changed
- test a build failure

## [0.0.252] - 2024-04-07
### Changed
- test a build failure

## [0.0.251] - 2024-04-07
### Fixed
- portable script

## [0.0.250] - 2024-04-07
### Fixed
- portable script

## [0.0.249] - 2024-04-07
### Changed
- learning pester I guess

## [0.0.248] - 2024-04-07
### Fixed
- test staging

## [0.0.247] - 2024-04-07
### Changed
- minify export-permissionportable

## [0.0.246] - 2024-04-07
### Changed
- minify export-permissionportable

## [0.0.245] - 2024-04-07
### Changed
- minify export-permissionportable

## [0.0.244] - 2024-04-07
### Changed
- minify export-permissionportable

## [0.0.243] - 2024-04-07
### Changed
- minify export-permissionportable

## [0.0.242] - 2024-04-07
### Changed
- minify export-permissionportable

## [0.0.241] - 2024-04-07
### Changed
- minify export-permissionportable

## [0.0.240] - 2024-04-07
### Changed
- minify export-permissionportable

## [0.0.239] - 2024-04-07
### Changed
- implement all groupby options for splitby target

## [0.0.238] - 2024-02-19
### Fixed
- access rights and scope in report

## [0.0.237] - 2024-02-18
### Fixed
- fake directory entry noteproperties getting dropped with get-member

## [0.0.236] - 2024-02-18
### Changed
- its alive

## [0.0.235] - 2024-02-18
### Changed
- its alive

## [0.0.234] - 2024-02-09
### Changed
- added output formatting

## [0.0.233] - 2024-02-05
### Changed
- more cim caching

## [0.0.232] - 2024-02-05
### Changed
- new adsi module version

## [0.0.231] - 2024-02-05
### Fixed
- cim cache misses

## [0.0.230] - 2024-02-05
### Changed
- oops prev build used old adsi module ver

## [0.0.229] - 2024-02-05
### Changed
- troubleshoot

## [0.0.228] - 2024-02-04
### Changed
- add cim caching

## [0.0.227] - 2024-02-04
### Changed
- working on CIM caching

## [0.0.226] - 2024-02-04
### Changed
- add cim caching

## [0.0.225] - 2024-02-04
### Changed
- removed start-sleep from prog bar debugging

## [0.0.224] - 2024-02-04
### Changed
- latest module versions and param name updates

## [0.0.223] - 2024-02-04
### Fixed
- fixed incorrect verb usage in member modules

## [0.0.222] - 2024-02-04
### Changed
- integrate ps 5.1 workarounds so ps 7 not required

## [0.0.221] - 2024-02-03
### Changed
- remove improper use of externalmoduledependencies

## [0.0.220] - 2024-02-02
### Changed
- removed unnecessary comment for property that already exists on object negating need for select-object

## [0.0.219] - 2024-02-02
### Changed
- migrated logic to permission module

## [0.0.218] - 2024-01-31
### Changed
- update psrunspace prog bars

## [0.0.217] - 2024-01-31
### Changed
- update psrunspace progress bars

## [0.0.216] - 2024-01-31
### Changed
- update psrunspace progress bars
### Fixed
- adsi

## [0.0.215] - 2024-01-31
### Changed
- updated adsi module workaround to ps class limitations with psrunspace

## [0.0.214] - 2024-01-28
### Changed
- update adsi module remove write-debug/warning

## [0.0.213] - 2024-01-28
### Fixed
- write-progress in psrunspace module

## [0.0.212] - 2024-01-28
### Fixed
- fakedirectoryentry class in adsi module

## [0.0.211] - 2024-01-28
### Fixed
- fakedirectoryentry class in adsi module

## [0.0.210] - 2024-01-28
### Changed
- reduce calls to external executables

## [0.0.209] - 2024-01-28
### Added
- write-progress in 1-thread mode

## [0.0.208] - 2024-01-28
### Changed
- updated progress and debug output

## [0.0.207] - 2024-01-27
### Fixed
- APPLICATION PACKAGE AUTHORITY identityreferences

## [0.0.206] - 2024-01-27
### Fixed
- APPLICATION PACKAGE AUTHORITY identityreferences

## [0.0.205] - 2024-01-27
### Fixed
- APPLICATION PACKAGE AUTHORITY identityreferences

## [0.0.204] - 2024-01-27
### Fixed
- resolve-identityreference in psadsi in resolve-identityreference invalid param when calling add-domainfqdntoldappath

## [0.0.203] - 2024-01-27
### Fixed
- resolve-identityreference in psadsi

## [0.0.202] - 2024-01-27
### Fixed
- psakefile (needed to filter out ProgressAction common param)

## [0.0.201] - 2024-01-27
### Fixed
- psakefile (needed to filter out ProgressAction common param)

## [0.0.200] - 2024-01-27
### Fixed
- psakefile (needed to filter out ProgressAction common param)

## [0.0.199] - 2024-01-27
### Fixed
- psakefile (needed to filter out ProgressAction common param)

## [0.0.198] - 2024-01-27
### Fixed
- psakefile (needed to filter out ProgressAction common param)

## [0.0.197] - 2024-01-27
### Fixed
- psakefile (needed to filter out ProgressAction common param)

## [0.0.196] - 2024-01-27
### Changed
- param names shortened

## [0.0.195] - 2024-01-21
### Changed
- new adsi module ver with clean transcript for nltest errors

## [0.0.194] - 2024-01-21
### Changed
- <https://github.com/IMJLA/Export-Permission/issues/61>

## [0.0.193] - 2024-01-21
### Changed
- enhancement-performance remove usage of select-object -first

## [0.0.192] - 2024-01-21
### Changed
- new PsNtfs and Permission module vers

## [0.0.191] - 2024-01-20
### Changed
- updated Permission module

## [0.0.190] - 2024-01-20
### Fixed
- owner feature

## [0.0.189] - 2024-01-20
### Changed
- had psakefile add module version to portable script version that is exported

## [0.0.188] - 2024-01-20
### Fixed
- psntfs

## [0.0.187] - 2024-01-20
### Fixed
- owner feature

## [0.0.186] - 2024-01-15
### Changed
- updated file names and new psntfs version with updated value for source column in 1st csv (dacl is now written out instead of acronym)

## [0.0.185] - 2024-01-15
### Changed
- added Source column to 1st CSV file to indicate DACL vs Ownership as source of access

## [0.0.184] - 2024-01-15
### Changed
- this time i really included a new ver of psntfs

## [0.0.183] - 2024-01-15
### Changed
- new psntfs version 2.0.68 adds feature to include owner in report

## [0.0.182] - 2024-01-15
### Changed
- new adsi module 4.0.5

## [0.0.181] - 2024-01-15
### Fixed
- new adsi module 4.0.4 with fakedirectoryentry class which fixes bugs in new-fakedirectoryentry

## [0.0.180] - 2024-01-15
### Fixed
- integrate new adsi module which solved adsi project issue 54

## [0.0.179] - 2024-01-15
### Changed
- updated version of adsi module

## [0.0.178] - 2024-01-15
### Fixed
- integrate new versions of PsDfs,PsDfs,PsRunspace for project issue 46

## [0.0.177] - 2024-01-15
### Changed
- minor updates to comment-based help

## [0.0.176] - 2024-01-15
### Changed
- updated comment-based help, updated version of Permission module

## [0.0.175] - 2024-01-14
### Changed
- updated permission module to update verbiage in final html report for the group membership exclusion

## [0.0.174] - 2024-01-14
### Changed
- new version of permission module

## [0.0.173] - 2024-01-14
### Changed
- new version of permission module

## [0.0.172] - 2024-01-14
### Changed
- new version of psbootstrapcss

## [0.0.171] - 2024-01-14
### Fixed
- fixed psake file to remove previously unnecessary feature which was instead implemented in new version of psbootstrapcss

## [0.0.170] - 2024-01-14
### Changed
- psakefile bug was generating invalid export-permissionportable scripts

## [0.0.169] - 2024-01-14
### Fixed
- project issue 49 in export-permissionportable by embedding external file content into script during psake build process

## [0.0.168] - 2024-01-14
### Changed
- gh issue 38 implemented ExcludeAccountClass param and deprecated ExcludeEmptyGroups switch

## [0.0.167] - 2024-01-13
### Added
- NoJavaScript switch
- @LogParams in Format-FolderPermission
### Fixed
- CsvFilePath3 ln725

## [0.0.166] - 2024-01-12
### Changed
- removed trailing whitespaces in comment-based help help header

## [0.0.165] - 2024-01-12
### Changed
- updated comments

## [0.0.164] - 2024-01-12
### Changed
- comment updates

## [0.0.163] - 2022-10-16
### Changed
- updated psbootstrapcss module

## [0.0.162] - 2022-09-05
### Fixed
- report footer

## [0.0.161] - 2022-09-05
### Changed
- Fine-tuning appearance of html report

## [0.0.160] - 2022-09-05
### Changed
- Completed enhancement issue 14

## [0.0.159] - 2022-09-04
### Fixed
- fixed issue 45

## [0.0.158] - 2022-09-04
### Fixed
- fixed issue 33 with new psrunspace version

## [0.0.157] - 2022-09-03
### Changed
- closed issue 27

## [0.0.156] - 2022-09-03
### Changed
- updated psntfs

## [0.0.155] - 2022-09-03
### Fixed
- Fixed Issue 3

## [0.0.154] - 2022-08-31
### Fixed
- IgnoreDomain was not working for 'Due to Membership In' column

## [0.0.153] - 2022-08-28
### Fixed
- Fixed bug 7 with updated psntfs module

## [0.0.152] - 2022-08-28
### Fixed
- Fixed bug with Expand-AccountPermission in psntfs module

## [0.0.151] - 2022-08-27
### Fixed
- Get-FolderTarget

## [0.0.150] - 2022-08-27
### Changed
- updated adsi module

## [0.0.149] - 2022-08-27
### Fixed
- $ExpandedAccountPermissions vs $FormattedSecurityPrincipals

## [0.0.148] - 2022-08-27
### Changed
- Added proper UNC and mapped drive functionality

## [0.0.147] - 2022-08-27
### Fixed
- psntfs for UNC folder targets

## [0.0.146] - 2022-08-27
### Fixed
- debug output for Get-AdsiServer

## [0.0.145] - 2022-08-27
### Fixed
- Fixed logging for Split-Thread -Command 'Get-AdsiServer'

## [0.0.144] - 2022-08-26
### Changed
- improved logging using PsLogMessage integrated with Adsi module

## [0.0.143] - 2022-08-25
### Changed
- Actually updated the Adsi module this time

## [0.0.142] - 2022-08-25
### Changed
- integrate latest changes from adsi dependency module

## [0.0.141] - 2022-08-25
### Changed
- cache improvements

## [0.0.140] - 2022-08-21
### Changed
- Updated module dependencies

## [0.0.139] - 2022-08-21
### Fixed
- Minor fixes to debug output

## [0.0.138] - 2022-08-21
### Changed
- replaced uint with uint16 for efficiency and ps 5.1 compat

## [0.0.137] - 2022-08-20
### Changed
- Test build to see if merge damage undone

## [0.0.136] - 2022-08-20
### Changed
- Updated psakefile to not publish unless working on main

## [0.0.135] - 2022-08-20
### Fixed
- Fixed mistakes from git merging

## [0.0.131] - 2022-08-20
### Fixed
- Fixed mistakes from git merging

## [0.0.130] - 2022-08-20
### Changed
- Moved ToDo list to GitHub Issues

## [0.0.129] - 2022-08-20
### Changed
- removed bug list from metadata, migrated to GitHub Issues

## [0.0.128] - 2022-08-20
### Changed
- Added blank lines for readability

## [0.0.127] - 2022-08-20
### Changed
- Changed some integers to unsigned integers where appropriate

## [0.0.126] - 2022-08-20
### Changed
- Minor script cleanup

## [0.0.125] - 2022-08-20
### Changed
- Now the pipeline support should actually halfway work

## [0.0.124] - 2022-08-19
### Changed
- Using hostname.exe instead of environment var due to maintaining configured capitalization of the hostname

## [0.0.123] - 2022-08-19
### Fixed
- Permission module

## [0.0.122] - 2022-08-19
### Changed
- Improved logging support via a single thread-safe hashtable to cache all log messages

## [0.0.121] - 2022-08-17
### Changed
- Had to create Resolve-Ace3 (identical clone of Resolve-Ace) for no known reason to solve an error, makes no sense

## [0.0.120] - 2022-08-14
### Changed
- Updated PsRunspace module and PsLogMessage module to allow for toggleable debug output

## [0.0.119] - 2022-08-14
### Changed
- Updated build with latest versions of module dependencies

## [0.0.118] - 2022-08-14
### Changed
- Updated build with latest versions of module dependencies

## [0.0.117] - 2022-08-07
### Changed
- Updated script metadata/comment-based help

## [0.0.116] - 2022-08-06
### Changed
- Updated notes

## [0.0.115] - 2022-08-06
### Changed
- Build with minor debug output changes and updated versions of module dependencies

## [0.0.114] - 2022-08-06
### Changed
- Updated script help

## [0.0.113] - 2022-08-06
### Fixed
- Updated modules with bugfixes

## [0.0.112] - 2022-08-01
### Changed
- Updated comment-based help

## [0.0.111] - 2022-08-01
### Changed
- Removed Feature from TODO list because it is implemented (commit msg as releasenotes in scriptfileinfo)

## [0.0.110] - 2022-08-01
### Changed
- Updated Permission module and some parameter help

## [0.0.109] - 2022-08-01
### Changed
- Parameter cleanup. Breaking changes.

## [0.0.108] - 2022-08-01
### Changed
- Added remaining blank lines where needed in metadata

## [0.0.107] - 2022-08-01
### Changed
- Trying blank lines in example help

## [0.0.106] - 2022-07-31
### Changed
- More blank lines in metadata

## [0.0.105] - 2022-07-31
### Changed
- Added blank lines to multiline param descriptions in comment-based help to workaround bug in New-MarkdownHelp

## [0.0.104] - 2022-07-31
### Changed
- metadata updates

## [0.0.104] - 2022-07-31
### Changed
- metadata updates

## [0.0.103] - 2022-07-31
### Changed
- metadata updates

## [0.0.102] - 2022-07-31
### Changed
- metadata updates

## [0.0.101] - 2022-07-31
### Changed
- metadata updates

## [0.0.100] - 2022-07-31
### Changed
- metadata updates

## [0.0.99] - 2022-07-31
### Changed
- metadata updates

## [0.0.98] - 2022-07-31
### Changed
- metadata updates

## [0.0.97] - 2022-07-31
### Changed
- Updated PsNtfs module

## [0.0.96] - 2022-07-31
### Changed
- Updated Adsi module

## [0.0.95] - 2022-07-31
### Changed
- Updated Adsi and PsNtfs modules, disabled automatic invocation of the HTML report file and replaced it with switch parameter

## [0.0.94] - 2022-07-31
### Changed
- Added feature to eliminate redundant calls to Get-AdsiServer for multiple threads that start at the same time and check the cache before it is populated

## [0.0.93] - 2022-07-30
### Changed
- Build with updated PsRunspace module

## [0.0.92] - 2022-07-30
### Changed
- Build with updated PsNtfs module

## [0.0.91] - 2022-07-30
### Fixed
- Bug fixes in Export-Permission and the PsRunspace module

## [0.0.90] - 2022-07-27
### Changed
- Updated PsNtfs module

## [0.0.89] - 2022-07-27
### Changed
- Integrate new version of PsNtfs for portable version

## [0.0.88] - 2022-07-27
### Changed
- Removed bug that was introduced trying to eliminate blank lines from portable script

## [0.0.87] - 2022-07-27
### Changed
- Initial publication to PSGallery, take 2

## [0.0.86] - 2022-07-27
### Changed
- Initial publication to PSGallery

## [0.0.85] - 2022-07-27
### Changed
- Prep for publishing to psgallery

## [0.0.84] - 2022-07-27
### Fixed
- Fixed bug in psakefile

## [0.0.83] - 2022-07-27
### Changed
- troubleshoot SourceControl task not running

## [0.0.82] - 2022-07-27
### Changed
- Test new psakefile

## [0.0.81] - 2022-07-27
### Changed
- Prep for psgallery upload

## [0.0.80] - 2022-07-27
### Changed
- frigging vscode adding quotes everywhere

## [0.0.79] - 2022-07-27
### Changed
- Test updated psakefile

## [0.0.78] - 2022-07-27
### Changed
- Updated PsBootstrapCss module to remove dependency on external .htm template file

## [0.0.77] - 2022-07-27
### Changed
- build without cab help

## [0.0.76] - 2022-07-27
### Changed
- Again

## [0.0.75] - 2022-07-27
### Changed
- Let's try this again

## [0.0.74] - 2022-07-27
### Changed
- Attempt build without external help cab

## [0.0.73] - 2022-07-26
### Changed
- Added New-Item to BuildReleaseForDistribution psake task

## [0.0.72] - 2022-07-26
### Changed
- Trying again

## [0.0.71] - 2022-07-26
### Changed
- Troubleshooting BuildMAMLHelp psake task

## [0.0.70] - 2022-07-26
### Changed
- Test build of new portable version

## [0.0.69] - 2022-07-26
### Changed
- Rebuild with updated version 1.0.14 of PsDfs module

## [0.0.68] - 2022-07-26
### Changed
- test

## [0.0.67] - 2022-07-26
### Changed
- test

## [0.0.66] - 2022-07-26
### Changed
- test updated build script

## [0.0.65] - 2022-07-26
### Changed
- Test updated psakefile

## [0.0.64] - 2022-07-26
### Fixed
- build script for portable script creation

## [0.0.63] - 2022-07-26
### Changed
- Test new build script's creation of portable script version

## [0.0.62] - 2022-07-25
### Changed
- test

## [0.0.61] - 2022-07-25
### Changed
- test

## [0.0.60] - 2022-07-25
### Changed
- test

## [0.0.59] - 2022-07-25
### Changed
- New build with updated module versions on build system for the portable version of the script

## [0.0.58] - 2022-07-25
### Changed
- testing again

## [0.0.57] - 2022-07-25
### Changed
- Troubleshooting the build task in psake

## [0.0.56] - 2022-07-25
### Changed
- Test new build feature

## [0.0.55] - 2022-07-25
### Fixed
- Bug fixes, typos caused by gnomes

## [0.0.54] - 2022-07-25
### Changed
- Rename for more accurate verb selection

## [0.0.56] - 2022-07-25
### Changed
- Test updated build script

## [0.0.55] - 2022-07-25
### Changed
- Test

## [0.0.54] - 2022-07-25
### Changed
- Rename to remove Ntfs in anticipation of future feature to support other providers

## [0.0.53] - 2022-07-25
### Fixed
- Module manifest

## [0.0.51] - 2022-07-10
### Changed
- Removed bundled modules in favor of #Requires statement and dependency on PSGallery

## [0.0.50] - 2022-07-08
### Changed
- Update module

## [0.0.49] - 2022-07-08
### Changed
- more troubleshooting

## [0.0.48] - 2022-07-08
### Changed
- troubleshooting tests

## [0.0.47] - 2022-07-08
### Changed
- Updated tests

## [0.0.46] - 2022-07-08
### Changed
- Applied UTF8 BOM to Get-ReportDescription for its infinity symbol

## [0.0.45] - 2022-07-08
### Changed
- Review PSScriptAnalyzer results

## [0.0.44] - 2022-07-08
### Changed
- Removed tabs in Metadata.tests.ps1

## [0.0.43] - 2022-07-08
### Changed
- Resolved more PSScriptAnalyzer issues

## [0.0.42] - 2022-07-08
### Changed
- Resolving PSScriptAnalyzer-detected issues

## [0.0.41] - 2022-07-08
### Changed
- Updated psakeFile

## [0.0.40] - 2022-07-08
### Changed
- Updated included Adsi module

## [0.0.39] - 2022-07-08
### Changed
- Updated log directory to use AppData

## [0.0.38] - 2022-07-07
### Changed
- troubleshooting Update-ScriptFileInfo

## [0.0.37] - 2022-07-05
### Changed
- Ready to go

## [0.0.36] - 2022-07-04
### Changed
- test

## [0.0.35] - 2022-07-04
### Changed
- test

## [0.0.34] - 2022-07-04
### Changed
- test

## [0.0.33] - 2022-07-04
### Changed
- test

## [0.0.32] - 2022-07-04
### Changed
- test

## [0.0.31] - 2022-07-04
### Changed
- test

## [0.0.30] - 2022-07-04
### Changed
- test

## [0.0.29] - 2022-07-04
### Changed
- First test after a successful build

## [0.0.28] - 2022-07-04
### Changed
- test

## [0.0.27] - 2022-07-04
### Changed
- test

## [0.0.26] - 2022-07-04
### Changed
- test

## [0.0.25] - 2022-07-04
### Changed
- test

## [0.0.24] - 2022-07-04
### Changed
- test

## [0.0.23] - 2022-07-04
### Changed
- test

## [0.0.22] - 2022-07-04
### Changed
- test

## [0.0.21] - 2022-07-04
### Changed
- test

## [0.0.20] - 2022-07-04
### Changed
- test

## [0.0.19] - 2022-07-04
### Changed
- test

## [0.0.18] - 2022-07-04
### Changed
- test

## [0.0.17] - 2022-07-04
### Changed
- test

## [0.0.16] - 2022-07-04
### Changed
- test

## [0.0.15] - 2022-07-04
### Changed
- test

## [0.0.14] - 2022-07-04
### Changed
- test

## [0.0.13] - 2022-07-04
### Changed
- test

## [0.0.12] - 2022-07-04
### Changed
- test

## [0.0.11] - 2022-07-04
### Changed
- test

## [0.0.10] - 2022-07-04
### Changed
- test

## [0.0.9] - 2022-07-04
### Changed
- test

## [0.0.8] - 2022-07-04
### Changed
- test

## [0.0.7] - 2022-07-04
### Changed
- test

## [0.0.6] - 2022-07-04
### Changed
- test

## [0.0.5] - 2022-07-04
### Changed
- test

## [0.0.4] - 2022-07-04
### Changed
- test

## [0.0.3] - 2022-07-04
### Changed
- test

## [0.0.2] - 2022-07-04
### Changed
- test

## [0.0.1] - 2022-07-04
### Added
- Initial commit
