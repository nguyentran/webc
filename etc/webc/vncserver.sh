#!/bin/bash

sudo ln -s /usr/bin/vnc4config /etc/alternatives/vncconfig
sudo ln -s /usr/bin/vnc4server /etc/alternatives/vncserver
sudo ln -s /usr/bin/vnc4passwd /etc/alternatives/vncpasswd
sudo ln -s /usr/bin/x0vnc4server /etc/alternatives/x0vncserver
sudo ln -s /usr/bin/Xvnc4 /etc/alternatives/Xvnc

sudo ln -s /etc/alternatives/vncconfig /usr/bin/vncconfig
sudo ln -s /etc/alternatives/vncserver /usr/bin/vncserver
sudo ln -s /etc/alternatives/vncpasswd /usr/bin/vncpasswd
sudo ln -s /etc/alternatives/x0vncserver /usr/bin/x0vncserver
sudo ln -s /etc/alternatives/Xvnc /usr/bin/Xvnc

