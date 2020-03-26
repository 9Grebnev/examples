#!/usr/bin/env bash

function log
{
    echo -e `date +"%d.%m.%Y %k:%M:%S "`"$1";
}

function d_promt
{
    printf "${WHITE}$1:${NC} "
}

function d_error
{
    echo -e "${LIGHTRED}$1${NC}";
}

function d_title
{
    echo -e "${GREEN}$1${NC}";
}

function d_info
{
    echo -e "${YELLOW}$1${NC}";
}