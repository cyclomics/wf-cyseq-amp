# wf-cyclomicsseq-amp


## Testing
Testing of this workflow is performed using [[nf-test](https://www.nf-test.com)].

There are a few types of tests in this repo, these tests should be tagged as such.
Each nextflow process should have unit test to test its behaviour, tagged as `unit-test`.
Additionally there sould be integration tests for sub-workflows if these are used.
Finally there should be end-to-end tests for the main workflow.

### Github actions
There are currently 3 github actions related to testing, this can be optimized with sharding later.

1. nf-test-ci-tests.yml
This runs all the nf-test tests and will run on pushes and PR's into main and dev

1. nf-test-unit-test.yml
This runs the all tests tagged as `unit-test` on PR's, but not on main and dev. As we run all the tests in that case already.

1. nf-test-changed-unit-test.yml
This runs the all tests tagged as `unit-test` that have been affected by changes on pushes, but not on main and dev. As we run all the tests in that case already.
