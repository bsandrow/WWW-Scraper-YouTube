use inc::Module::Install;
use strict;

name 'WWW-Scraper-YouTube';
all_from 'lib/WWW/Scraper/YouTube.pm';

install_script 'getyt';
install_script 'getyt-gui';

WriteAll;
