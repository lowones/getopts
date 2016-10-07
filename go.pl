#!/usr/bin/perl -w
use strict;
use Getopt::Std;
require "/home/lowk/bin/lowlib.pl";

my (%app, %prc, %options) = ();
#
###	SETUP

getopts('apib?', \%options);
if ( $options{'?'} )
	{ usage(); }
###	MAIN

if	 ( $options{'i'} )
	{ print"i\n"; }
elsif	 ( $options{'b'} )
	{ print"b\n"; }
else
	{ print"default\n"; }

###	END	MAIN
