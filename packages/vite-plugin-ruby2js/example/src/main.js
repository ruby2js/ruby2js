import { add, multiply, greet } from './math.rb';

const output = document.getElementById('output');
output.innerHTML = `
  <p>add(2, 3) = ${add(2, 3)}</p>
  <p>multiply(4, 5) = ${multiply(4, 5)}</p>
  <p>greet("World") = ${greet("World")}</p>
`;
