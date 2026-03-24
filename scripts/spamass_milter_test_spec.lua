--The script was taken from here and shortened: https://manpages.ubuntu.com/manpages/jammy/en/man8/miltertest.8.html

socket_path = os.getenv("SPAMASS_SOCKET_PATH")
if socket_path == nil then
    mt.echo("SPAMASS_SOCKET_PATH not set. Skipping")
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
reply = mt.getreply(conn)
if reply ~= SMFIR_CONTINUE  and reply ~= SMFIR_ACCEPT then
    error "mt.conninfo() unexpected reply"
end

-- send envelope macros and sender data
-- mt.helo() is called implicitly
mt.macro(conn, SMFIC_MAIL, "i", "test-id")
if mt.mailfrom(conn, "user@example.com") ~= nil then
    error "mt.mailfrom() failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.mailfrom() unexpected reply"
end

-- send headers
-- mt.rcptto() is called implicitly
if mt.header(conn, "From", "user@example.com") ~= nil then
    error "mt.header(From) failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.header(From) unexpected reply"
end
if mt.header(conn, "Date", os.date("%a, %d %b %Y %H:%M:%S %z")) ~= nil then
    error "mt.header(Date) failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.header(Date) unexpected reply"
end
if mt.header(conn, "Received", "from mail-vs1-f71.google.com (mail-vs1-f71.google.com\n" ..
        "    [209.85.217.71]) (Using TLS) by relay.mimecast.com with ESMTP id\n" ..
        "    us-mta-152-adtPER30NqGkJJmUbRyRBg-1; " ..
        os.date("%a, %d %b %Y %H:%M:%S %z")) ~= nil then
    error "mt.header(Received) failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.header(Received) unexpected reply"
end
if mt.header(conn, "Message-ID", "<MQDQEagfJkw=eD8BSjVKY_PdAG=0cLzqn76ViD8r2AVNdqnax0w@mail.gmail.com>") ~= nil then
    error "mt.header(Message-ID) failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.header(Message-ID) unexpected reply"
end
if mt.header(conn, "Subject", "Milter test") ~= nil then
    error "mt.header(Subject) failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.header(Subject) unexpected reply"
end
if mt.header(conn, "To", "user@example.com") ~= nil then
    error "mt.header(To) failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.header(To) unexpected reply"
end
-- send EOH
if mt.eoh(conn) ~= nil then
    error "mt.eoh() failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.eoh() unexpected reply"
end

-- send body
if mt.bodystring(conn, "This is a test!\r\n") ~= nil then
    error "mt.bodystring() failed"
end
if mt.getreply(conn) ~= SMFIR_CONTINUE then
    error "mt.bodystring() unexpected reply"
end
-- end of message; let the filter react
if mt.eom(conn) ~= nil then
    error "mt.eom() failed"
end
reply = mt.getreply(conn)
if reply ~= SMFIR_ACCEPT and reply ~= SMFIR_CONTINUE then
    error "mt.eom() unexpected reply"
end

-- wrap it up!
mt.disconnect(conn, true)