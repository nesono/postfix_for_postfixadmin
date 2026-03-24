--The script was taken from here and shortened: https://manpages.ubuntu.com/manpages/jammy/en/man8/miltertest.8.html

socket_path = os.getenv("DKIM_SOCKET_PATH")
if socket_path == nil then
    mt.echo("DKIM_SOCKET_PATH not set. Skipping")
    os.exit(0)
end

conn = mt.connect("unix:/var/spool/postfix/" .. socket_path)
if conn == nil then
    error "mt.connect() failed"
end

-- send connection information
-- mt.negotiate() is called implicitly
if mt.conninfo(conn, "localhost", "127.0.0.1") ~= nil then
    error "mt.conninfo() failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.conninfo() unexpected reply"
end

-- wrap it up!
mt.disconnect(conn, true)