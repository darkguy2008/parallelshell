'use strict';
process.on('beforeExit', () => {
    throw new Error('test is waiting on an event that can never arrive');
});
