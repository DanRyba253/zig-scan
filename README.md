# zig-scan

Formatted input functions for zig

## Description

This project provides functions similar to scanf/sscanf from libc.  
Created mostly for my personal ergonomics when doing AoC

## Dependencies

Zig v0.13.0

## Getting Started

Run this command in your project directory to fetch this repo and update your build.zig.zon:
```
zig fetch --save https://github.com/DanRyba253/zig-scan/archive/refs/tags/v0.0.0.tar.gz
```

Then, update your build.zig to expose the relevant module to your executable
```
    const zig_scan = b.dependency("zig-scan", .{
        .target = target,
        .optimize = optimize,
    });
    const module = zig_scan.module("zig-scan");
    exe.root_module.addImport("zig-scan", module);
```

## Documentation

### Overview

This package provides four functions: `scan`, `scanOut`, `bufScan` and `bufScanOut`  
  
Functions that start with "buf" parse from a buffer of type `[]const u8`  
Functions that don't start with "buf" parse from a provided `std.io.Reader`  
Functions that end with "Out" take in a tuple of pointers where they will output parsed values  
Functions that don't end with "Out" return a tuple of parsed values

### Format specifiers

Format specifiers start with '{' and end with '}'.  
To use '{' or '}' as normal characters instead of escape characters, repeat them.  
  
{iN} captures a value of type `iN` written in base 10, N could be any integer between 0 and 65535  
{iN:b} captures a value of type `iN` written in base b  
{uN} captures a value of type `uN` written in base 10  
{uN:b} captures a value of type `uN` written in base b  
{usize} captues a value of type `usize` written in base 10  
{usize:b} captures a value of type `usize` written in base b  
{fN} captures a value of type `fN` written in base 10, N could be equal to 16, 32 or 64  
{c} captures a single character in a form of a `u8`  
{_} consumes all consecutive whitespace characters, but does not capture anything.  
{s} and {b} specifiers are used to capture strings. They are described more thoroughly below.

### Terminator characters
By default both {s} and {b} capture and consume all consecutive non-whitespace characters.  
***Note: unlike in C, {s} and {b} do not consume leading or trailing whitespace.***  
You can add any character at the end to signify a "terminator" character. For example:  
{s,} captures all consecutive characters until it reaches a comma  
{b#} captures all consecutive characters until it reaches a hash  
***Note: when used this way, the "terminator" character is consumed from input, but isn't captured***

### What's the difference between {s} and {b}?
The difference between {s} and {b} is how they capture strings.  

{s} is only available for functions that end with "Out", i.e. that expect a tuple of pointers.  
{s} makes a function expect a value of type `*[]u8`. It will copy the captured string into this slice and change it's length to match the length of the captured string.  
Example of use:
```
var buf:[100]u8 = undefined;
var name:[]u8 = buf[0..50];
var surname:[]u8 = buf[50..];

const input = "John Doe";

try bufScanOut("{s} {s}", input, .{&name, &surname});

std.debug.assert(std.mem.eql(u8, name, "John"));
std.debug.assert(std.mem.eql(u8, surname, "Doe"));
```
{s} works similarly to how "%s" works in C.  

{b} is only available for functions that start with "buf", i.e. those that read from a buffer.  
when used with 'bufScan', {b} will make it return a slice of the original buffer that contains the captured string.  
when used with 'bufScanOut', {b} will make it expect a value of type `*[]const u8` and will put into it a slice of the original buffer that contains the captured string.  
Example of use:
```
var name: []const u8 = undefined;
var surname: []const u8 = undefined;

const input = "John Doe";

try bufScanOut("{b} {b}", input, .{&name, &surname});

std.debug.assert(std.mem.eql(u8, name, "John"));
std.debug.assert(std.mem.eql(u8, surname, "Doe"));
```
{b} is named like this because it only works with ***B***uffers.

### Misc. stuff

* `scan` and `scanOut` take an extra comptime parameter called `buf_len` which is used to initialize an internal buffer used to temporarily store reader output. Make sure that `buf_len` > length of any sequence in between format specifiers in your format string. And `buf_len` > length of any part of input captured by format specifiers.

* `scan` and `scanOut` may make a lot of successive calls to the supplied reader, so it is recommended to wrap it in std.io.bufferedReader first for performance.

* unlike functions in libc, functions provided in this package do not return the number of successfully parsed arguments.

* unlike functions in libc, The "fmt" parameter to any of the functions provided here has to be comptime-known.

* for more examples of use check out src/zig-scan.zig test suite.

## Version History

* 0.0.0
    * Initial Release

## License

This project is licensed under the MIT License - see the LICENSE.md file for details
