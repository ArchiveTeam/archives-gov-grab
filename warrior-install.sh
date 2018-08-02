if ! sudo pip freeze | grep -q warc==0.2.1
then
  echo "Installing warc 0.2.1"
  if ! sudo pip install warc --upgrade
  then
    exit 1
  fi
fi

exit 0


