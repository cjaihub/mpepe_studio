"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_REQUIREMENTS = exports.BUSINESS_TYPES = void 0;
exports.mergeRequirements = mergeRequirements;
exports.docsFor = docsFor;
exports.matches = matches;
exports.BUSINESS_TYPES = ['sole_trader', 'company', 'partnership', 'nonprofit', 'public_body'];
const ANY_ID = '^[A-Z0-9][A-Z0-9 ./-]{2,39}$';
exports.DEFAULT_REQUIREMENTS = {
    country: 'default',
    registry: 'the official business registry in your country',
    registrationNumber: { label: 'Registration number', hint: 'As printed on your registration certificate', pattern: ANY_ID, required: true },
    taxId: { label: 'Tax ID', hint: 'Your business tax number', pattern: ANY_ID, required: false },
    ownershipThreshold: 25,
    documents: [
        { key: 'registration_certificate', label: 'Registration certificate', hint: 'Certificate of incorporation or business name registration', required: true },
        { key: 'ownership_record', label: 'Ownership record', hint: 'Official list of directors and shareholders', required: true, types: ['company', 'partnership'] },
        { key: 'tax_certificate', label: 'Tax registration', hint: 'Certificate showing your tax ID', required: false },
        { key: 'proof_of_address', label: 'Proof of address', hint: 'Utility bill, lease or bank statement, less than 3 months old', required: true },
    ],
    notes: '',
};
const BUILT_IN = {
    KE: {
        registry: 'Business Registration Service (BRS)',
        registrationNumber: { label: 'BRS registration number', hint: 'e.g. PVT-ABC1234 or BN-XYZ5678', pattern: '^[A-Z]{2,4}[- /]?[A-Z0-9]{4,14}$', required: true },
        taxId: { label: 'KRA PIN', hint: '11 characters, e.g. P051234567X', pattern: '^[AP][0-9]{9}[A-Z]$', required: true },
        documents: [
            { key: 'registration_certificate', label: 'Certificate of incorporation or business name certificate', hint: 'From the BRS / eCitizen', required: true },
            { key: 'ownership_record', label: 'CR12', hint: 'Recent CR12 listing directors and shareholders', required: true, types: ['company'] },
            { key: 'tax_certificate', label: 'KRA PIN certificate', hint: 'From iTax', required: true },
            { key: 'proof_of_address', label: 'Proof of address', hint: 'Utility bill, lease or bank statement, less than 3 months old', required: true },
        ],
    },
    NG: {
        registry: 'Corporate Affairs Commission (CAC)',
        registrationNumber: { label: 'CAC number', hint: 'e.g. RC1234567 or BN1234567', pattern: '^(RC|BN|IT|LP|LLP)?[ -]?[0-9]{4,9}$', required: true },
        taxId: { label: 'TIN', hint: 'Tax identification number', pattern: '^[0-9]{8,14}(-[0-9]{4})?$', required: true },
    },
    US: {
        registry: 'your state’s Secretary of State',
        registrationNumber: { label: 'State filing number', hint: 'From your articles of organization or incorporation', pattern: ANY_ID, required: true },
        taxId: { label: 'EIN', hint: '9 digits, e.g. 12-3456789', pattern: '^[0-9]{2}-?[0-9]{7}$', required: true },
    },
    GB: {
        registry: 'Companies House',
        registrationNumber: { label: 'Company number', hint: '8 characters, e.g. 01234567 or SC123456', pattern: '^([0-9]{8}|[A-Z]{2}[0-9]{6})$', required: true },
        taxId: { label: 'UTR', hint: '10-digit Unique Taxpayer Reference', pattern: '^[0-9]{10}$', required: false },
    },
};
function mergeRequirements(country, stored) {
    var _a;
    const base = Object.assign(Object.assign(Object.assign({}, exports.DEFAULT_REQUIREMENTS), ((_a = BUILT_IN[country]) !== null && _a !== void 0 ? _a : {})), (stored !== null && stored !== void 0 ? stored : {}));
    return Object.assign(Object.assign({}, base), { country });
}
function docsFor(req, type) {
    return req.documents.filter((d) => !d.types || d.types.includes(type));
}
function matches(field, value) {
    if (!value)
        return !field.required;
    try {
        return new RegExp(field.pattern, 'i').test(value);
    }
    catch (_a) {
        return value.length >= 3;
    }
}
//# sourceMappingURL=requirements.js.map