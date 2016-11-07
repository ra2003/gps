import GPS
from . import core
import os
import types
from workflows.promises import ProcessWrapper, join, wait_idle


@core.register_vcs
class Git(core.VCS):

    def __init__(self, repo):
        super(self.__class__, self).__init__(repo)

    def setup(self):
        self._override_status_display(
            GPS.VCS2.Status.STAGED_MODIFIED,
            'modified (staged)', 'gps-emblem-vcs-modified')

    @staticmethod
    def discover_repo(file):
        return core.find_admin_directory(file, '.git')

    def __git_ls_tree(self):
        """
        Compute all files under version control
        """
        all_files = set()
        dir = os.path.normpath(os.path.join(self.repo, '..'))
        p = ProcessWrapper(
            ['git', 'ls-tree', '-r', 'HEAD', '--name-only'],
            directory=dir)
        while True:
            line = yield p.wait_line()
            if line is None:
                GPS.Logger("GIT").log("finished ls-tree")
                yield all_files
                break
            all_files.add(GPS.File(os.path.join(dir, line)))

    def __git_status(self, s):
        """
        Run and parse "git status"
        :param s: the result of calling self.set_status_for_all_files
        """
        dir = os.path.normpath(os.path.join(self.repo, '..'))
        p = ProcessWrapper(
            ['git', 'status', '--porcelain', '--ignored'],
            directory=dir)
        while True:
            line = yield p.wait_line()
            if line is None:
                GPS.Logger("GIT").log("finished git-status")
                break

            if len(line) > 3:
                if line[0:2] in ('DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'):
                    status = GPS.VCS2.Status.CONFLICT
                else:
                    status = 0

                    if line[0] == 'M':
                        status = GPS.VCS2.Status.STAGED_MODIFIED
                    elif line[0] == 'A':
                        status = GPS.VCS2.Status.STAGED_ADDED
                    elif line[0] == 'D':
                        status = GPS.VCS2.Status.STAGED_DELETED
                    elif line[0] == 'R':
                        status = GPS.VCS2.Status.STAGED_RENAMED
                    elif line[0] == 'C':
                        status = GPS.VCS2.Status.STAGED_COPIED
                    elif line[0] == '?':
                        status = GPS.VCS2.Status.UNTRACKED
                    elif line[0] == '!':
                        status = GPS.VCS2.Status.IGNORED

                    if line[1] == 'M':
                        status = status | GPS.VCS2.Status.MODIFIED
                    elif line[1] == 'D':
                        status = status | GPS.VCS2.Status.DELETED

                # Filter some obvious files to speed things up
                if line[-3:] != '.o' and line[-5:] != '.ali':
                    s.set_status(GPS.File(os.path.join(dir, line[3:])), status)

    def async_fetch_status_for_files(self, files):
        self.async_fetch_status_for_all_files(files)

    @core.run_in_background
    def async_fetch_status_for_all_files(self, extra_files=[]):
        """
        :param List(GPS.File) extra_files: files for which we need to
           set the status eventually
        """
        s = self.set_status_for_all_files(GPS.VCS2.Status.UNMODIFIED)
        a = yield join(self.__git_ls_tree(), self.__git_status(s))
        GPS.Logger("GIT").log("set status for all remaining files extra=%s"
                              % (extra_files, ))
        f = a[0]
        f.update(extra_files)
        s.set_status_for_remaining_files(f)
        GPS.Logger("GIT").log("done set status for all remaining files")
