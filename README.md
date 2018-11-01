This is the full code for Triagebot, a GitHub App that automatically triages incoming issues, as detailed on the [GitHub Blog](https://blog.github.com/2018-10-31-automating-issue-triage-with-github-and-recastai/).

If you just want to _use_ Triagebot, you can install it into your repos [on the app install page](https://github.com/apps/don-s-triage-bot)

If you want to learn how to build and run this for yourself, this is the right place to be. Triagebot is based upon the [GitHub App Quickstart](https://developer.github.com/apps/building-your-first-github-app/)

## Install and run

* First, read through the [blog post](https://blog.github.com/2018-10-31-automating-issue-triage-with-github-and-recastai/) so you understand all the additional steps you'll need to take to make a complete GitHub App with the [Recast.AI](https://recast.ai/) API.

* To run the code, make sure you have [Bundler](http://gembundler.com/) installed; then enter `bundle install` on the command line.

* The server will run on `localhost:3000`. Use this information to configure [Smee](https://smee.io/) as per the instructions above.
