#!/usr/bin/env bash

#
# vdsok lamp functions
#
# (c) 2017-2018, VDSok
#

vdsok_lamp_install() { lamp_install && [[ "${IAM,,}" == 'debian' ]]; }

setup_vdsok_lamp() {
  debug '# setup vdsok lamp'
  setup_lamp || return 1
  if debian_buster_image; then
    setup_adminer || return 1
  else
    setup_phpmyadmin || return 1
  fi
  setup_webmin
}

# vim: ai:ts=2:sw=2:et
