// Integration tests for the workflow builder demo
// Tests CRUD operations, validations, associations, and controller actions
// Uses better-sqlite3 with :memory: for fast, isolated tests

import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIST_DIR = join(__dirname, 'workspace/workflow/dist');

// Dynamic imports - loaded once in beforeAll
let Workflow, Node, Edge;
let WorkflowsController, NodesController, EdgesController;
let Application, initDatabase, migrations, modelRegistry;

// Note: The workflow Show view uses React Flow with browser-only pragmas.
// Testing it would require mocking React Flow. See notes.test.mjs for
// React Testing Library patterns that could be adapted here.

describe('Workflow Builder Integration Tests', () => {
  beforeAll(async () => {
    // Import the active_record adapter (for initDatabase and modelRegistry)
    const activeRecord = await import(join(DIST_DIR, 'lib/active_record.mjs'));
    initDatabase = activeRecord.initDatabase;
    modelRegistry = activeRecord.modelRegistry;

    // Import Application from rails.js
    const rails = await import(join(DIST_DIR, 'lib/rails.js'));
    Application = rails.Application;

    // Import migrations
    const migrationsModule = await import(join(DIST_DIR, 'db/migrate/index.js'));
    migrations = migrationsModule.migrations;

    // Import models
    const models = await import(join(DIST_DIR, 'app/models/index.js'));
    Workflow = models.Workflow;
    Node = models.Node;
    Edge = models.Edge;

    // Import controllers
    const workflowsCtrl = await import(join(DIST_DIR, 'app/controllers/workflows_controller.js'));
    WorkflowsController = workflowsCtrl.WorkflowsController;

    const nodesCtrl = await import(join(DIST_DIR, 'app/controllers/nodes_controller.js'));
    NodesController = nodesCtrl.NodesController;

    const edgesCtrl = await import(join(DIST_DIR, 'app/controllers/edges_controller.js'));
    EdgesController = edgesCtrl.EdgesController;

    // Configure Application with migrations
    Application.configure({ migrations });
    Application.registerModels({ Workflow, Node, Edge });

    // Register models with adapter's registry for association resolution
    modelRegistry.Workflow = Workflow;
    modelRegistry.Node = Node;
    modelRegistry.Edge = Edge;
  });

  beforeEach(async () => {
    // Initialize fresh in-memory database for each test
    await initDatabase({ database: ':memory:' });

    // Get the adapter module for runMigrations
    const adapter = await import(join(DIST_DIR, 'lib/active_record.mjs'));

    // Run migrations using Application
    await Application.runMigrations(adapter);
  });

  describe('Workflow Model', () => {
    it('creates a workflow with valid attributes', async () => {
      const workflow = await Workflow.create({
        name: 'Test Workflow'
      });

      expect(workflow.id).toBeDefined();
      expect(workflow.name).toBe('Test Workflow');
      expect(workflow.id).toBeGreaterThan(0);
    });

    it('validates name presence', async () => {
      const workflow = new Workflow({ name: '' });
      const saved = await workflow.save();

      expect(saved).toBe(false);
      expect(workflow.errors.name).toBeDefined();
    });

    it('finds workflow by id', async () => {
      const created = await Workflow.create({ name: 'Find Me' });

      const found = await Workflow.find(created.id);
      expect(found.name).toBe('Find Me');
    });

    it('lists all workflows', async () => {
      await Workflow.create({ name: 'Workflow 1' });
      await Workflow.create({ name: 'Workflow 2' });

      const workflows = await Workflow.all();
      expect(workflows.length).toBe(2);
    });

    it('updates a workflow', async () => {
      const workflow = await Workflow.create({ name: 'Original' });

      await workflow.update({ name: 'Updated' });

      const reloaded = await Workflow.find(workflow.id);
      expect(reloaded.name).toBe('Updated');
    });

    it('destroys a workflow', async () => {
      const workflow = await Workflow.create({ name: 'To Delete' });
      const id = workflow.id;

      await workflow.destroy();

      const found = await Workflow.findBy({ id });
      expect(found).toBeNull();
    });
  });

  describe('Node Model', () => {
    let workflow;

    beforeEach(async () => {
      workflow = await Workflow.create({ name: 'Test Workflow' });
    });

    it('creates a node with valid attributes', async () => {
      const node = await Node.create({
        workflow_id: workflow.id,
        label: 'Start',
        node_type: 'input',
        position_x: 100,
        position_y: 50
      });

      expect(node.id).toBeDefined();
      expect(node.label).toBe('Start');
      expect(node.position_x).toBe(100);
      expect(node.position_y).toBe(50);
    });

    it('validates position_x presence', async () => {
      const node = new Node({
        workflow_id: workflow.id,
        label: 'Test',
        position_y: 50
      });
      const saved = await node.save();

      expect(saved).toBe(false);
      expect(node.errors.position_x).toBeDefined();
    });

    it('validates position_y presence', async () => {
      const node = new Node({
        workflow_id: workflow.id,
        label: 'Test',
        position_x: 100
      });
      const saved = await node.save();

      expect(saved).toBe(false);
      expect(node.errors.position_y).toBeDefined();
    });

    it('validates label presence', async () => {
      const node = new Node({
        workflow_id: workflow.id,
        label: '',
        position_x: 100,
        position_y: 50
      });
      const saved = await node.save();

      expect(saved).toBe(false);
      expect(node.errors.label).toBeDefined();
    });

    it('belongs to workflow association', async () => {
      const node = await Node.create({
        workflow_id: workflow.id,
        label: 'Test Node',
        position_x: 100,
        position_y: 50
      });

      const parentWorkflow = await node.workflow;
      expect(parentWorkflow.id).toBe(workflow.id);
      expect(parentWorkflow.name).toBe('Test Workflow');
    });

    it('workflow has many nodes', async () => {
      await Node.create({ workflow_id: workflow.id, label: 'Node 1', position_x: 100, position_y: 50 });
      await Node.create({ workflow_id: workflow.id, label: 'Node 2', position_x: 200, position_y: 50 });

      const reloaded = await Workflow.includes('nodes').find(workflow.id);
      expect(reloaded.nodes.length).toBe(2);
    });

    it('updates node position', async () => {
      const node = await Node.create({
        workflow_id: workflow.id,
        label: 'Movable',
        position_x: 100,
        position_y: 50
      });

      await node.update({ position_x: 200, position_y: 150 });

      const reloaded = await Node.find(node.id);
      expect(reloaded.position_x).toBe(200);
      expect(reloaded.position_y).toBe(150);
    });
  });

  describe('Edge Model', () => {
    let workflow, sourceNode, targetNode;

    beforeEach(async () => {
      workflow = await Workflow.create({ name: 'Test Workflow' });
      sourceNode = await Node.create({
        workflow_id: workflow.id,
        label: 'Source',
        position_x: 100,
        position_y: 50
      });
      targetNode = await Node.create({
        workflow_id: workflow.id,
        label: 'Target',
        position_x: 300,
        position_y: 50
      });
    });

    it('creates an edge with valid attributes', async () => {
      const edge = await Edge.create({
        workflow_id: workflow.id,
        source_node_id: sourceNode.id,
        target_node_id: targetNode.id
      });

      expect(edge.id).toBeDefined();
      expect(edge.source_node_id).toBe(sourceNode.id);
      expect(edge.target_node_id).toBe(targetNode.id);
    });

    it('belongs to source_node association', async () => {
      const edge = await Edge.create({
        workflow_id: workflow.id,
        source_node_id: sourceNode.id,
        target_node_id: targetNode.id
      });

      const source = await edge.source_node;
      expect(source.id).toBe(sourceNode.id);
      expect(source.label).toBe('Source');
    });

    it('belongs to target_node association', async () => {
      const edge = await Edge.create({
        workflow_id: workflow.id,
        source_node_id: sourceNode.id,
        target_node_id: targetNode.id
      });

      const target = await edge.target_node;
      expect(target.id).toBe(targetNode.id);
      expect(target.label).toBe('Target');
    });

    it('workflow has many edges', async () => {
      const middleNode = await Node.create({
        workflow_id: workflow.id,
        label: 'Middle',
        position_x: 200,
        position_y: 50
      });

      await Edge.create({ workflow_id: workflow.id, source_node_id: sourceNode.id, target_node_id: middleNode.id });
      await Edge.create({ workflow_id: workflow.id, source_node_id: middleNode.id, target_node_id: targetNode.id });

      const reloaded = await Workflow.includes('edges').find(workflow.id);
      expect(reloaded.edges.length).toBe(2);
    });
  });

  describe('WorkflowsController', () => {
    it('index action returns workflow list', async () => {
      await Workflow.create({ name: 'Listed Workflow' });

      const context = {
        params: {},
        flash: { get: () => '', consumeNotice: () => '', consumeAlert: () => '' },
        contentFor: {}
      };

      const html = await WorkflowsController.index(context);
      expect(html).toContain('Listed Workflow');
      expect(html).toContain('Workflows');
    });

    it('create action adds a new workflow', async () => {
      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {}
      };

      const params = { workflow: { name: 'New Workflow' } };

      const result = await WorkflowsController.create(context, params);

      expect(result.redirect).toBeDefined();

      const workflows = await Workflow.all();
      expect(workflows.length).toBe(1);
      expect(workflows[0].name).toBe('New Workflow');
    });

    it('update action modifies workflow', async () => {
      const workflow = await Workflow.create({ name: 'Original Name' });

      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {}
      };

      const params = { workflow: { name: 'New Name' } };

      await WorkflowsController.update(context, workflow.id, params);

      const reloaded = await Workflow.find(workflow.id);
      expect(reloaded.name).toBe('New Name');
    });

    it('destroy action removes workflow', async () => {
      const workflow = await Workflow.create({ name: 'To Delete' });

      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {}
      };

      await WorkflowsController.destroy(context, workflow.id);

      const workflows = await Workflow.all();
      expect(workflows.length).toBe(0);
    });
  });

  describe('NodesController', () => {
    let workflow;

    beforeEach(async () => {
      workflow = await Workflow.create({ name: 'Test Workflow' });
    });

    it('create action adds a node to workflow', async () => {
      const context = {
        params: {},
        contentFor: {}
      };

      const params = {
        node: {
          label: 'New Node',
          node_type: 'default',
          position_x: 150,
          position_y: 75
        }
      };

      await NodesController.create(context, workflow.id, params);

      // Verify node was created in database
      const nodes = await Node.where({ workflow_id: workflow.id });
      expect(nodes.length).toBe(1);
      expect(nodes[0].label).toBe('New Node');
    });

    it('update action modifies node', async () => {
      const node = await Node.create({
        workflow_id: workflow.id,
        label: 'Original',
        position_x: 100,
        position_y: 50
      });

      const context = {
        params: {},
        contentFor: {}
      };

      const params = { node: { label: 'Updated Label' } };

      await NodesController.update(context, workflow.id, node.id, params);

      const reloaded = await Node.find(node.id);
      expect(reloaded.label).toBe('Updated Label');
    });

    it('destroy action removes node', async () => {
      const node = await Node.create({
        workflow_id: workflow.id,
        label: 'To Delete',
        position_x: 100,
        position_y: 50
      });

      const context = {
        params: {},
        contentFor: {}
      };

      await NodesController.destroy(context, workflow.id, node.id);

      const nodes = await Node.where({ workflow_id: workflow.id });
      expect(nodes.length).toBe(0);
    });
  });

  describe('EdgesController', () => {
    let workflow, sourceNode, targetNode;

    beforeEach(async () => {
      workflow = await Workflow.create({ name: 'Test Workflow' });
      sourceNode = await Node.create({
        workflow_id: workflow.id,
        label: 'Source',
        position_x: 100,
        position_y: 50
      });
      targetNode = await Node.create({
        workflow_id: workflow.id,
        label: 'Target',
        position_x: 300,
        position_y: 50
      });
    });

    it('create action adds an edge', async () => {
      const context = {
        params: {},
        contentFor: {}
      };

      const params = {
        edge: {
          source_node_id: sourceNode.id,
          target_node_id: targetNode.id
        }
      };

      const result = await EdgesController.create(context, workflow.id, params);

      expect(result.id).toBeDefined();

      const edges = await Edge.where({ workflow_id: workflow.id });
      expect(edges.length).toBe(1);
    });

    it('destroy action removes edge', async () => {
      const edge = await Edge.create({
        workflow_id: workflow.id,
        source_node_id: sourceNode.id,
        target_node_id: targetNode.id
      });

      const context = {
        params: {},
        contentFor: {}
      };

      await EdgesController.destroy(context, workflow.id, edge.id);

      const edges = await Edge.where({ workflow_id: workflow.id });
      expect(edges.length).toBe(0);
    });
  });

  describe('Query Interface', () => {
    beforeEach(async () => {
      await Workflow.create({ name: 'Alpha' });
      await Workflow.create({ name: 'Beta' });
      await Workflow.create({ name: 'Gamma' });
    });

    it('where filters by attributes', async () => {
      const results = await Workflow.where({ name: 'Beta' });
      expect(results.length).toBe(1);
      expect(results[0].name).toBe('Beta');
    });

    it('order sorts results', async () => {
      const results = await Workflow.order({ name: 'desc' });
      expect(results[0].name).toBe('Gamma');
      expect(results[2].name).toBe('Alpha');
    });

    it('limit restricts result count', async () => {
      const results = await Workflow.limit(2);
      expect(results.length).toBe(2);
    });

    it('first returns single record', async () => {
      const first = await Workflow.first();
      expect(first).toBeDefined();
    });

    it('count returns record count', async () => {
      const count = await Workflow.count();
      expect(count).toBe(3);
    });
  });

  describe('Path Helpers', () => {
    let workflows_path, workflow_path, new_workflow_path, edit_workflow_path;
    let nodes_path, node_path;

    beforeAll(async () => {
      const paths = await import(join(DIST_DIR, 'config/paths.js'));
      workflows_path = paths.workflows_path;
      workflow_path = paths.workflow_path;
      new_workflow_path = paths.new_workflow_path;
      edit_workflow_path = paths.edit_workflow_path;
      nodes_path = paths.nodes_path;
      node_path = paths.node_path;
    });

    it('workflows_path returns correct path', () => {
      // Use String() since path helpers return objects with toString() methods
      expect(String(workflows_path())).toBe('/workflows');
    });

    it('workflow_path returns correct path with id', async () => {
      const workflow = await Workflow.create({ name: 'Test' });
      // Use String() since path helpers return objects with toString() methods
      expect(String(workflow_path(workflow))).toBe(`/workflows/${workflow.id}`);
    });

    it('new_workflow_path returns correct path', () => {
      // Use String() since path helpers return objects with toString() methods
      expect(String(new_workflow_path())).toBe('/workflows/new');
    });

    it('edit_workflow_path returns correct path', async () => {
      const workflow = await Workflow.create({ name: 'Test' });
      // Use String() since path helpers return objects with toString() methods
      expect(String(edit_workflow_path(workflow))).toBe(`/workflows/${workflow.id}/edit`);
    });

    it('nodes_path returns nested path', async () => {
      const workflow = await Workflow.create({ name: 'Test' });
      // Use String() since path helpers return objects with toString() methods
      expect(String(nodes_path(workflow))).toBe(`/workflows/${workflow.id}/nodes`);
    });

    it('path helpers should not double the base path', () => {
      const path = String(workflows_path());
      expect(path).not.toContain('/workflows/workflows');
    });
  });

  describe('Cascade Delete', () => {
    it('deleting workflow removes associated nodes', async () => {
      const workflow = await Workflow.create({ name: 'Cascade Test' });
      await Node.create({ workflow_id: workflow.id, label: 'Node 1', position_x: 100, position_y: 50 });
      await Node.create({ workflow_id: workflow.id, label: 'Node 2', position_x: 200, position_y: 50 });

      await workflow.destroy();

      const nodes = await Node.all();
      expect(nodes.length).toBe(0);
    });

    it('deleting workflow removes associated edges', async () => {
      const workflow = await Workflow.create({ name: 'Cascade Test' });
      const node1 = await Node.create({ workflow_id: workflow.id, label: 'Node 1', position_x: 100, position_y: 50 });
      const node2 = await Node.create({ workflow_id: workflow.id, label: 'Node 2', position_x: 200, position_y: 50 });
      await Edge.create({ workflow_id: workflow.id, source_node_id: node1.id, target_node_id: node2.id });

      await workflow.destroy();

      const edges = await Edge.all();
      expect(edges.length).toBe(0);
    });
  });
});
