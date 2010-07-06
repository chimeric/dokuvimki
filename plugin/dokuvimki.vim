"-----------------------------------------------------------------------------
" Copyright (C) 2008 Michael Klier <chi@chimeric.de>
"
" This program is free software; you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation; either version 2, or (at your option)
" any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program; if not, write to the Free Software Foundation,
" Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.  
"
" Maintainer:   Michael Klier <chi@chimeric.de>
" URL:          http://www.chimeric.de/projects/dokuwiki/dokuvimki
"-----------------------------------------------------------------------------

" Command definitions
command! -nargs=1 DWEdit exec('py dokuvimki.edit(<f-args>)')
command! -nargs=? DWSave exec('py dokuvimki.save(<f-args>)')
command! -nargs=? DWSearch exec('py dokuvimki.search(<f-args>)')
command! -nargs=* DWRevisions exec('py dokuvimki.revisions(<f-args>)')
command! -nargs=? DWBacklinks exec('py dokuvimki.backlinks(<f-args>)')
command! -nargs=? DWChanges exec('py dokuvimki.changes(<f-args>)')
command! -nargs=0 DWClose exec('py dokuvimki.close()')
command! -nargs=0 DWHelp exec('py dokuvimki.help()')
command! -nargs=0 DokuVimKi exec('py dokuvimki()')

python <<EOF
# -*- coding: utf-8 -*-

__version__ = '2010-07-01';
__author__  = 'Michael Klier <chi@chimeric.de>'

import sys
import re
import vim
import time
import tempfile
sys.path.append('/home/chi/.vim/plugin/dokuwikixmlrpc')

# TODO
# map :ls to own python function to only list open wiki pages without special buffers
# global quit mapping
# FIXME check if a pages was modified but not send!!!
# media stuff?
# disable stuff if xmlrpc fails!
# package that damned python module - update?
# FIXME diffing?
# ~/bin script for launching
# re-auth to another wiki (parallel sessions?)
# improve dictionary lookup (needs autocomplete function)
# FIXME check if a pages was modified but not send!!!
# help
# test id_lookup()
# nicer highlighting for revisions
# FIXME provide easy way to show number of last changes (DWChanges 1week etc.)
# FIXME DWSaveAll
# FIXME remove all locks on quit of all buffers in the pages list


class DokuVimKi:
    """
    Provides all necessary functionality to interface between the DokuWiki
    XMLRPC API and vim.
    """


    def __init__(self):
        """
        Instantiates special buffers, setup the xmlrpc connection and loads the
        page index and displays the recent changes of the last 7 days.
        """

        self.buffers = {}
        self.buffers['search']    = Buffer('search', 'nofile')
        self.buffers['backlinks'] = Buffer('backlinks', 'nofile')
        self.buffers['revisions'] = Buffer('revisions', 'nofile')
        self.buffers['changes']   = Buffer('changes', 'nofile')
        self.buffers['index']     = Buffer('index', 'nofile')
        self.buffers['help']      = Buffer('help', 'nofile')

        self.cur_ns = ''
        self.pages  = []

        self.dict = tempfile.NamedTemporaryFile(suffix='.dokuvimki')
        vim.command('set dict+=' + self.dict.name)

        self.xmlrpc_init()
        self.index(self.cur_ns, True)
        vim.command('silent! 30vsplit')
        self.changes()
        

    def xmlrpc_init(self):
        """
        Establishes the xmlrpc connection to the remote wiki.
        """

        self.dw_user = vim.eval('g:DokuVimKi_USER')
        self.dw_pass = vim.eval('g:DokuVimKi_PASS')
        self.dw_url  = vim.eval('g:DokuVimKi_URL')

        try:
            import dokuwikixmlrpc
        except ImportError:
            print >>sys.stderr, 'DokuVimKi Error: The dokuwikixmlrpc python module is missing! Disabling all DokuVimKi commands!'
            # FIXME disable all the shit

        try:
            self.xmlrpc = dokuwikixmlrpc.DokuWikiClient(self.dw_url, self.dw_user, self.dw_pass)
            print >>sys.stdout, 'Connection to ' + vim.eval('g:DokuVimKi_URL') + ' established!'
        except dokuwikixmlrpc.DokuWikiXMLRPCError, msg:
            print >>sys.stderr, msg


    def edit(self, wp, rev=''):
        """
        Opens a given wiki page, or a given revision of a wiki page for
        editing or switches to the correct buffer if the is open already.
        """

        self.focus(2)

        if not self.buffers.has_key(wp):

            perm = int(self.xmlrpc.acl_check(wp))

            if perm >= 1:
                try:
                    if rev:
                        text = self.xmlrpc.page(wp, int(rev))
                    else:
                        text = self.xmlrpc.page(wp)
                except StandardError, err:
                    # FIXME better error handling
                    print >>sys.stdout, err

                if text: 
                    if perm == 1:
                        print >>sys.stderr, "You don't have permission to edit %s. Opening readonly!" % wp
                        self.buffers[wp] = Buffer(wp, 'nowrite', True)

                    if perm >= 2:
                        if not self.lock(wp):
                            # FIXME use exceptions
                            return

                        print >>sys.stdout, "Opening %s for editing ..." % wp
                        self.buffers[wp] = Buffer(wp, 'acwrite', True)

                    lines = text.split("\n")
                    self.buffers[wp].buf[:] = map(lambda x: x.encode('utf-8'), lines)

                    vim.command('autocmd! BufWriteCmd <buffer> py dokuvimki.save(<f-args>)')
                    vim.command('autocmd! FileWriteCmd <buffer> py dokuvimki.save(<f-args>)')
                    vim.command('autocmd! FileAppendCmd <buffer> py dokuvimki.save(<f-args>)')

                if not text and perm >= 4:
                    print >>sys.stdout, "Creating new page: %s" % wp
                    self.buffers[wp]   = Buffer(wp, 'acwrite', True)
                    self.needs_refresh = True

                    vim.command('autocmd! BufWriteCmd <buffer> py dokuvimki.save(<f-args>)')
                    vim.command('autocmd! FileWriteCmd <buffer> py dokuvimki.save(<f-args>)')
                    vim.command('autocmd! FileAppendCmd <buffer> py dokuvimki.save(<f-args>)')

                vim.command('set encoding=utf-8')
                vim.command('setlocal textwidth=0')
                vim.command('setlocal wrap')
                vim.command('setlocal linebreak')
                vim.command('setlocal syntax=dokuwiki')
                vim.command('setlocal filetype=dokuwiki')

                vim.command('map <buffer> <silent> e :py dokuvimki.id_lookup()<CR>')

            else:
                print >>sys.stderr, "You don't have permissions to read/edit/create %s" % wp
                return

        else:
            self.needs_refresh = False
            vim.command('silent! buffer! ' + self.buffers[wp].num)


    def save(self, sum='', minor=0):
        """
        Saves the current buffer. Works only if the buffer is a wiki page.
        Deleting wiki pages works like using the web interface, just delete all
        text and save.
        """
        
        wp = vim.current.buffer.name.rsplit('/', 1)[1]
        if not self.buffers[wp].iswp: 
            print >>sys.stderr, "Error: Current buffer %s is not a wiki page!" % wp
        elif self.buffers[wp].type == 'nowrite':
            print >>sys.stderr, "Error: Current buffer %s is readonly!" % wp
        else:
            text = "\n".join(self.buffers[wp].buf)

            if not sum and text:
                sum = 'xmlrpc edit'
                minor = 1

            try:
                self.xmlrpc.put_page(wp, text, sum, minor)

                if text:
                    vim.command('silent! buffer! ' + self.buffers[wp].num)
                    vim.command('set nomodified')
                    print >>sys.stdout, 'Page %s written!' % wp
                    if self.needs_refresh:
                        self.index(self.cur_ns, True)
                        self.needs_refresh = False
                        self.focus(2)
                else:
                    self.close()
                    self.index(self.cur_ns, True)
                    self.focus(2)
                    print >>sys.stdout, 'Page %s removed!' % wp

            except StandardError, err:
                # FIXME better error handling
                print >>sys.stderr, 'DokuVimKi Error: %s' % err

    
    def index(self, query='', refresh=False):
        """
        Build the index used to navigate the remote wiki.
        """

        index = []
        pages = []
        dirs  = []

        self.focus(1)

        vim.command('silent! buffer! ' + self.buffers['index'].num)
        vim.command('setlocal modifiable')
        vim.command('setlocal nonumber')
        vim.command('syn match DokuVimKi_NS /^.*\//')
        vim.command('syn match DokuVimKi_CURNS /^ns:/')
        vim.command('hi DokuVimKi_NS cterm=bold ctermfg=LightBlue')
        vim.command('hi DokuVimKi_CURNS cterm=bold ctermfg=Yellow')

        # FIXME ???
        if refresh:
            self.refresh()

        if query and query[-1] != ':':
            self.edit(query)
            return
        else:
            self.cur_ns = query

        for page in self.pages:
            if not query:
                if page.find(':', 0) == -1:
                    pages.append(page)
                else:
                    ns = page.split(':', 1)[0] + '/'
                    if ns not in dirs:
                        dirs.append(ns)
            else:
                if re.search('^' + query, page):
                    page = page.replace(query, '')
                    if page.find(':') == -1:
                        if page not in index:
                            pages.append(page)
                    else:
                        ns = page.split(':', 1)[0] + '/'
                        if ns not in dirs:
                            dirs.append(ns)


        index.append('ns: ' + self.cur_ns)

        if query:
            index.append('.. (up a namespace)')

        index.append('')

        pages.sort()
        dirs.sort()
        index = index + dirs + pages

        self.buffers['index'].buf[:] = index

        vim.command('map <silent> <buffer> <enter> :py dokuvimki.cmd("index")<CR>')
        vim.command('map <silent> <buffer> r :py dokuvimki.cmd("revisions")<CR>')
        vim.command('map <silent> <buffer> b :py dokuvimki.cmd("backlinks")<CR>')

        vim.command('setlocal nomodifiable')


    def changes(self, timestamp=False):
        """
        Shows the last changes on the remote wiki.
        """
        
        self.focus(2)

        vim.command('silent! buffer! ' + self.buffers['changes'].num)
        vim.command('setlocal modifiable')

        if not timestamp:
            timestamp = int(time.time()) - (60*60*24*7)

        try:
            changes = self.xmlrpc.recent_changes(timestamp)
            lines = []
            if len(changes) > 0:
                for change in changes:
                    line = "\t".join(map(lambda x: str(change[x]), ['name', 'lastModified', 'version', 'author']))
                    lines.append(line)
                
                lines.reverse()
                self.buffers['changes'].buf[:] = lines
                vim.command('map <silent> <buffer> <enter> :py dokuvimki.rev_edit()<CR>')
                vim.command('setlocal nomodifiable')
            else:
                print >>sys.stderr, 'DokuVimKi Error: No changes'
        except StandardError, err:
            print >>sys.stderr, err


    def revisions(self, wp='', first=0):
        """
        Display revisions for a certain page if any.
        """

        if not wp or wp[-1] == ':':
            return

        self.focus(2)

        vim.command('silent! buffer! ' + self.buffers['revisions'].num)
        vim.command('setlocal modifiable')

        try:
            revs = self.xmlrpc.page_versions(wp, int(first))
            lines = []
            if len(revs) > 0:
                for rev in revs:
                    line = wp + "\t" + "\t".join(map(lambda x: str(rev[x]), ['modified', 'version', 'ip', 'type', 'user', 'sum']))
                    lines.append(line)
                
                self.buffers['revisions'].buf[:] = lines
                print >>sys.stdout, "loaded revisions for :%s" % wp
                vim.command('map <silent> <buffer> <enter> :py dokuvimki.rev_edit()<CR>')
                vim.command('setlocal nomodifiable')
            else:
                print >>sys.stderr, 'DokuVimKi Error: No revisions found for page: %s' % wp

        except StandardError, err:
            print >>sys.stderr, 'DokuVimKi XML-RPC Error: %s' % err


    def backlinks(self, wp=''):
        """
        Display backlinks for a certain page if any.
        """

        if not wp or wp[-1] == ':':
            return

        self.focus(2)

        vim.command('silent! buffer! ' + self.buffers['backlinks'].num)
        vim.command('setlocal modifiable')

        try:
            blinks = self.xmlrpc.backlinks(wp)

            if len(blinks) > 0:
                for link in blinks:
                    self.buffers['backlinks'].buf[:] = map(str, blinks)
                vim.command('map <buffer> <enter> :py dokuvimki.cmd("edit")<CR>')
                vim.command('setlocal nomodifiable')
            else:
                print >>sys.stderr, 'DokuVimKi Error: No backlinks found for page: %s' % wp

        except DokuWikiXMLRPCError, err:
            print >>sys.stderr, 'DokuVimKi XML-RPC Error: %s' % err


    def search(self, pattern='', refresh=False):
        """
        Search the page list for matching pages and display them for editing.
        """

        self.focus(2)

        if refresh:
            self.refresh()

        try:
            vim.command('silent! buffer! ' + self.buffers['search'].num)
            del self.buffers['search'].buf[:]

            if pattern:
                p = re.compile(pattern)
                result = filter(p.search, self.pages)
            else:
                result = self.pages

            if len(result) > 0:
                self.buffers['search'].buf[:] = result
                vim.command('map <buffer> <enter> :py dokuvimki.cmd("edit")<CR>')
            else:
                print >>sys.stderr, 'DokuVimKi Error: No matching pages found!'
        except:
            pass
    

    def close(self):
        """
        Closes the current buffer. Works only if the current buffer is a wiki
        page.  The buffer is also removed from the buffer stack.
        """

        wp = vim.current.buffer.name.rsplit('/', 1)[1]
        if self.buffers[wp].iswp: 
            vim.command('bp!')
            vim.command('bdel! ' + self.buffers[wp].num)
            if self.buffers[wp].type == 'acwrite':
                # FIXME test for success?
                self.unlock(wp)
            del self.buffers[wp]
        else:
            print >>sys.stderr, 'You cannot close special buffer "%s"!' % wp


    def help(self):
        """
        FIXME show help
        """

        self.focus(2)
        vim.command('silent! buffer! ' + self.buffers['help'].num)


    def rev_edit(self):
        """
        Special mapping for editing revisions from the revisions listing.
        """

        row, col = vim.current.window.cursor
        wp  = vim.current.buffer[row-1].split("\t")[0]
        rev = vim.current.buffer[row-1].split("\t")[2]
        self.edit(wp, rev)


    def focus(self, winnr):
        """
        Convenience function to switch the current window focus.
        """

        if int(vim.eval('winnr()')) != winnr:
            vim.command(str(winnr) + 'wincmd w')

    
    def refresh(self):
        """
        Refreshes the page index by retrieving a fresh list of all pages on the
        remote server and updating the completion dictionary.
        """

        print >>sys.stdout, "Refreshing page index!"
        data = self.xmlrpc.all_pages()
        self.pages = []

        if data:
            for page in data:
                self.pages.append(page['id'].encode('utf-8'))

        self.pages.sort()
        self.dict.seek(0)
        self.dict.write("\n".join(self.pages))


    def lock(self, wp):
        """
        Tries to obtain a lock given wiki page.
        """

        locks = {}
        locks['lock']   = [ wp ]
        locks['unlock'] = []

        result = self.set_locks(locks)

        if locks['lock'] == result['locked']:
            print >>sys.stdout, "Locked page %s for editing. You have to wait until the lock expires." % wp
            return True
        else:
            print >>sys.stderr, "Failed to lock page %s" % wp
            return False

    
    def unlock(self, wp):
        """
        Tries to unlock a given wiki page.
        """

        locks = {}
        locks['lock']   = []
        locks['unlock'] = [ wp ]

        result = self.set_locks(locks)
        if locks['unlock'] == result['unlocked']:
            return True
        else:
            print >>sys.stderr, "Failed to unlock page %s" % wp
            return False


    def set_locks(self, locks):
        """
        Locks unlocks a given set of pages.
        """

        try:
            return self.xmlrpc.set_locks(locks)
        except StandardError, err:
            # FIXME error handling
            print >>sys.stderr, err


    def id_lookup(self):
        """
        When editing pages, hiting enter while over a wiki link will open the
        page. This functions tries to guess the correct wiki page.
        """
        line = vim.current.line
        row, col = vim.current.window.cursor

        # get namespace from current page
        wp = vim.current.buffer.name.rsplit('/', 1)[1]
        ns = wp.rsplit(':', 1)[0]
        if ns == wp:
            ns = ''

        # look for link syntax on the left and right from the current curser position
        reL = re.compile('\[{2}[^]]*$') # opening link syntax
        reR = re.compile('^[^\[]*]{2}') # closing link syntax

        L = reL.search(line[:col])
        R = reR.search(line[col:])

        # if both matched we probably have a link
        if L and R:

            # sanitize match remove anchors and everything after '|'
            id = (L.group() + R.group()).strip('[]').split('|')[0].split('#')[0]

            # check if it's not and external/interwiki/share link
            if id.find('>') == -1 and id.find('://') == -1 and id.find('\\') == -1:

                # check if useshlash is used
                if id.find('/'):
                    id = id.replace('/', ':')

                # this is _almost_ a rip off of DokuWikis resolve_id() function
                if id[0] == '.':
                    re_sanitize = re.compile('(\.(?=[^:\.]))')
                    id = re_sanitize.sub('.:', id)
                    id = ns + ':' + id
                    path = id.split(':')

                    result = []
                    for dir in path:
                        if dir == '..':
                            try:
                                if result[-1] == '..':
                                    result.append('..')
                                elif not result.pop():
                                    result.append('..')
                            except IndexError:
                                pass
                        elif dir and dir != '.' and not len(dir.split('.')) > 2:
                            result.append(dir)

                    id = ':'.join(result)

                elif ns and id[0] != ':' and id.find(':', 0) == -1:
                    id = ns + ':' + id

                # we're done, open the page for editing
                print >>sys.stdout, id
                self.edit(id)


    def cmd(self, cmd):
        """
        Callback function to provides various functionality for the page index
        (like open namespaces or triggering edit showing backlinks etc).
        """

        row, col = vim.current.window.cursor
        line = vim.current.buffer[row-1]

        # first line triggers nothing
        if row == 1: 
            print >>sys.stdout, "meh"
            return

        if line.find('..') == -1:
            if line.find('/') == -1:
                if not line:
                    print >>sys.stdout, "meh"
                else:
                    line = self.cur_ns + line
            else:
                line = self.cur_ns + line.replace('/', ':')
        else:
            line = self.cur_ns.rsplit(':', 2)[0] + ':'
            if line == ":" or line == self.cur_ns:
                line = ''

        callback = getattr(self, cmd)
        callback(line)


class Buffer():
    """
    Representates a vim buffer object. Used to manage keep track of all opened
    pages and to handle the dokuvimki special buffers.

        self.num    = buffer number (starts at 1)
        self.id     = buffer id (starts at 0)
        self.buf    = vim buffer object
        self.name   = buffer name   
        self.iswp   = True if buffer represents a wiki page
    """

    id     = None
    num    = None
    name   = None
    buf    = None

    def __init__(self, name, type, iswp=False):
        """
        Instanziates a new buffer.
        """
        vim.command('badd ' + name)
        self.num  = vim.eval('bufnr("' + name + '")')
        self.id   = int(self.num) - 1
        self.buf  = vim.buffers[self.id]
        self.name = name
        self.iswp = iswp
        self.type = type
        vim.command('silent! buffer! ' + self.num)
        vim.command('setlocal buftype=' + type)
        vim.command('abbr <buffer> <silent> close DWClose')


def dokuvimki():
    global dokuvimki
    dokuvimki = DokuVimKi()

# vim:ts=4:sw=4:et:enc=utf-8:
