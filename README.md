puzbl
=====

Puzbl - frontend interface to uzbl browser written on Perl + Gtk 2.

Control keys:
- create a new tab: Ctrl-t;
- close an existing tab: Ctrl-w;
- change url in address bar: Ctrl-l;
- select the n-th tab: Alt-<n>
- switch between tabs: Shift-<left>, Shift-<right>.

Control using uzbl:
- create a new tab: gn;
- close an existing tab: gC;
- change url in address bar: o<u>;
- select the n-th tab: gi<n>;
- switch between tabs: gt, gT, g<, g>.

Control via fifo:
- create a new tab: add <u>;
- close an existing tab: del <n>;
- change url in address bar: url <u>;
- select the n-th tab: goto <n>;
- switch between tabs: prev, next, first, last.

Branitskiy Alexander <schurshik at yahoo dot com>
